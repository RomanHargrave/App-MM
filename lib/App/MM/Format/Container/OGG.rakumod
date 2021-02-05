use experimental :pack;
use NativeCall;

#| Pure raku Ogg stream reader/writer.
unit module App::MM::Tags::Format::OGG is export;

# yeah, well we'll deal with correct extensions later I guess
# i really only care about linux.
my constant CRCImpSO = %?RESOURCES<lib/libogg_crc32.so>;

sub ogg_crc32(uint32 $crc, Buf $buf, size_t $len --> uint32) is native(CRCImpSO) {*};

my constant PageCont = 1; #= Page continues a packet (something something lacing, nobody ever does this)
my constant PageBOS  = 2; #= Page begins a logical stream
my constant PageEOS  = 4; #= Page ends a logical stream

#| Reads OGG data, emitting packets
class OGGReader is export {
   my constant Cap    = 'OggS'.encode;
   my constant CapNum = Cap.read-uint32: 0; #= 0x5367674F
   my constant CapCRC = ogg_crc32(0, Cap, Cap.bytes);
   
   has IO::Handle $.in is readonly is required;

   has Bool $.no-checksum = False;
   has Bool $.hunt = False;

   has $!packet-buf = Buf.new;
   has @!packet-inf = Array.new;
   has %!eos;
   has %!stbuf;
   has $!mtx = Lock.new;
   
   # capture stream sync (realign stream)
   method !capture-sync(UInt :$threshold = 512) {
      when $.hunt {
         my $mb = $.in.read: 4;
         for 0..$threshold -> $off {
            return if $mb.read-uint32($off) == CapNum;
            warn "Searching for capture pattern";
            $mb.push: $.in.read(1);
         }
         die "Can't capture sync after reading $threshold bytes. Is this an Ogg stream?";
      }
      default {
         die "Capture pattern not found" unless $.in.read(4).read-uint32(0) == CapNum;
      }
   }
   
   method !read-page {
      self!capture-sync;

      my $hdr = $.in.read: 23;
   
      #my $version     = $hdr.read-uint8:   0; # + 1 = 1
      my $flags       = $hdr.read-uint8:   1; # + 1 = 2
      #my $granule-pos = $hdr.read-int64:   2; # + 8 = 10
      my $serial      = $hdr.read-uint32: 10; # + 4 = 14
      my $seq         = $hdr.read-uint32: 14; # + 4 = 18
      my $crc         = $hdr.read-uint32: 18; # + 4 = 22
      my $segments    = $hdr.read-uint8:  22; # + 1 = 23

      my $lvs-buf     = $.in.read: $segments;  # Lacing values
      my $body-size   = $lvs-buf.Array.reduce: &[+];

      # suck in page and maybe do checksum
      my $body = $.in.read: $body-size;

      # bail if the stream is already marked as eos
      # optimization: remove edge case check?
      die "Encountered terminated stream $serial while reading a new page" if %!eos{$serial};

      my $eos = ($flags +& PageEOS).so;
      
      %!eos{$serial} = True if $eos; # try to avoid useless hash access here 
      
      unless $.no-checksum {
         $hdr.write-uint32: 18, 0; # clear the CRC as it was written
         my uint32 $crc-eff = CapCRC;
         $crc-eff = ogg_crc32($crc-eff, $hdr, $hdr.bytes);
         $crc-eff = ogg_crc32($crc-eff, $lvs-buf, $lvs-buf.bytes);
         $crc-eff = ogg_crc32($crc-eff, $body, $body.bytes);

         warn "CRC Mismatch for page {$serial}#{$seq}: got $crc-eff but expected $crc" unless $crc-eff == $crc;
      }

      $!mtx.protect: {
         # grab the packet buffer for this logical stream
         my $buf = %!stbuf{$serial} //= Buf.new;

         # flush stream buf into packet buffer if there's residual data but this is a fresh page
         if $buf && ($flags +& PageCont).not {
            @!packet-inf.push: ($serial, $buf.bytes);
            $!packet-buf.push: $buf;
            $buf.reallocate: 0;
         }

         # consume body by lacing value
         while $_ = $lvs-buf.shift {
            $buf.append: $body.splice(0, $_); # take the segment off the top of the body

            # if the lv is <255, this is the end of a packet (RFC3533 §5), flush it
            if $_ < 255 {
               @!packet-inf.push: ($serial, $buf.bytes);
               $!packet-buf.push: $buf;
               $buf.reallocate: 0;
            }
         }

         # if there's data in the buffer but this is an EOS page, flush it
         if $eos && $buf {
            @!packet-inf.push: ($serial, $buf.bytes);
            $!packet-buf.push: $buf;
            # no point in reallocating
            %!stbuf{$serial}:delete;
         }
      }
   }

   method packets {
      fail "EOF" if $.in.eof;

      # do initial packet load
      # self!read-page until $.in.eof || $!packets-available;

      lazy gather {
         loop {
            # do initial buffer fill
            self!read-page until $!packet-buf;

            # unload buffer
            while @!packet-inf {
               my ($id, $size) = @!packet-inf.shift;
               take ($id, $!packet-buf.splice: 0, $size)
            }

            last if $.in.eof;
         }
      }
   }
}

=begin pod
=head1 OGG Container Implementation

This is an implementation of OGG (the container, not Vorbis) that is suitable (at the least)
for reading and writing metadata (tags).

Support has been implemented according to L<RFC3533|https://xiph.org/ogg/doc/rfc3533.txt>.

=head2 Reading OGG Files

C<
use App::MM::Format::Container::OGG;

my $r = OGGReader.new: :in('file.ogg'.IO.open);

for $r.packets -> ($stream-id, $packet-data-buf) {
   # do some stuff
}
>

=end pod
