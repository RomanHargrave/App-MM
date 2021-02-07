use NativeCall;

#| Raku bindings to libogg
unit module App::MM::Tags::Format::LibOGG is export;

my constant lib = ('ogg', 0);

# suck a pointer into a Buf
sub slurp-ptr(Pointer $ptr, size_t $n --> Blob[uint8]) {
   my $buf = Buf.allocate: $n;
   my $buf-ptr = nativecast(Pointer, $buf);
   memcpy($buf, $ptr, $n);
   $buf;
}

#| Corresponds to C<struct ogg_page>
#| Encapsulates data for an ogg page
class Page is repr<CStruct> is export(:ALL) {
   #| Pointer to the header for this page
   has Pointer[uint8] $.header-ptr;
   #| Length of page header in bytes
   has long $.header-len;

   #| Pointer to data for this page
   has Pointer[uint8] $.body-ptr;
   #| Length of page data (body) in bytes
   has long $.body-len;
}

#| Corresponds to C<struct ogg_stream_state>
#| Tracks encode/decode state of the current logical bitstream
class StreamState is repr<CStruct> is export(:ALL) {
   #| Pointer to data from packet bodies
   has Pointer[uint8] $.body-data;
   #| Storage allocated for bodies in bytes (filled or unfilled)
   has int64 $.body-storage;
   #| Amount of storage filled with packet bodies
   has int64 $.body-fill;
   #| Number of elements returned from storage
   has int64 $.body-returned;
   #| Lacing values for the packet segments in the current page
   has Pointer[uint8] $.lacing-vals;
   #| Pointer to the lacing values for the packet segments within the current page
   has Pointer[int64] $.granule-vals;
   #| Total storage in bytes allocated for storing lacing values
   has int64 $.lacing-storage;
   #| Fill marker for lacing values
   has int64 $.lacing-fill;
   #| Lacing value for current segment
   has int64 $.lacing-packet;
   #| Number of lacing values returned from lacing storage
   has int64 $.lacing-returned;
   #| Temporary storage for page header
   HAS uint8 @.header[282] is CArray;
   #| Fill marker for header storage
   has int32 $.header-fill;
   #| Set when the last packet has been buffered
   has int32 $.eos;
   #| Set after first page has been writted
   has int32 $.bos;
   #| Serial number of this bitstream
   has int64 $.serial;
   #| Current page within the stream
   has int64 $.pageno;
   #| Number of the current packet
   has int64 $.packetno;
   #| Exact position of encoding/decoding process
   has int64 $.granulepos;

   method new(int32 $serial-number) {
      my $s = self.CREATE;
      given ogg_stream_init($s, $serial-number) {
         when 0 { $s }
         default { fail "Could not init {::?CLASS.name}: LibOGG returned $_" }
      }
   }

   submethod DESTROY() {
      ogg_stream_destroy(self);
   }
}

#| Corresponds to C<struct ogg_packet>
#| Encapsulates the data for a single raw packet of data and is used to transfer
#| data between the ogg framing layer and the handling codec
class Packet is repr<CStruct> is export(:ALL) {
   #| Pointer to the packet's data
   #| This is an int because NativeCall is mean
   #| and for some reason pointer members are immutable attrs
   has uint64 $.contents is rw;
   #| Size of packet data in bytes
   has long $.content-size is rw;
   #| Indicates whether this packet begins a logical bitstream
   #| 1 indicates the first packet, 0 any other.
   has long $.bos is rw;
   #| Indicates whether this packet ends a bitstream.
   #| 1 indicates the last packet, 0 any other.
   has long $.eos is rw;
   #| A number indicating the position of this packet in the decoded data.
   #| This is the last sample, frame, or other unit of information (granule) that
   #| can be completely decoded from this packet.
   has int64 $.granule-pos is rw;
   #| Sequential number of this packet in the ogg bitstream.
   has int64 $.packet-number is rw;

   method contents-ptr {
      use nqp;
      nqp::box_i($.contents, Pointer); # bite me
   }
}

#| Corresponds to C<struct ogg_sync_state>
#| Tracks the synchronization of the current page. 
class SyncState is repr<CStruct> is export(:ALL) {
   #| Pointer to buffered stream data
   has Pointer $.data-ptr;
   #| Current allocated size of the current buffer heald in C<data-ptr>
   has int32 $.storage;
   #| Number of valid bytes currently held in C<data-ptr>
   #| Functions as buffer head pointer
   has int32 $.fill;
   #| Number of valid bytes at the head of C<data-ptr>
   has int32 $.returned;
   #| Number of bytes at the head of C<data-ptr> that have
   #| already been returned as pages. Functions as buffer tail pointer.
   has int32 $.unsynced;
   #| If synced, the number of bytes used by the synced page's header
   has int32 $.headerbytes;
   #| If synced, the number of bytes used by the synced page's body
   has int32 $.bodybytes;

   method new() {
      my $s = self.CREATE;
      given ogg_sync_init($s) {
         when 0 { $s }
         default { fail "Could not init {::?CLASS.name}: LibOGG returned $_" }
      }
   }
   
   submethod DESTROY() {
      ogg_sync_destroy(self);
   }
}

# ---- HLI ----

class LOGGReader is export {
   class PacketData {
      has $.serial;
      has $.contents;
      has $.granule-pos;
      has $.eos;
      has $.bos;
      has $.packet-number;

      method Blob(--> Blob) { $!contents };
   }

   has IO::Handle $.in is required;
   has $!chunk-size = 4096;
   
   has SyncState $!sync .= new;   #= Overall sync state
   has %!streams;                 #= StreamStates
   
   has Page $!page      .= new;   #= Page holding area
   has Packet $!packet  .= new;   #= Packet holding area

   has Lock $!mtx       .= new;

   #| consume available data in $in
   method !read {
      if $!in.eof {
         warn "EOF";
         return False if $!in.eof;
      }

      my $buf         = ogg_sync_buffer($!sync, $!chunk-size);
      my $data        = $!in.read: $!chunk-size;
      my size_t $size = $data.bytes;

      memcpy($buf, $data, $size);

      my $status = ogg_sync_wrote($!sync, $size);

      die "An error occurred in libOGG" unless $status == 0;

      return True;
   }
   
   # read enough data to obtain a packet from the first stream that has one available
   method read-packet {
      $!mtx.protect: {
         self!read until $!in.eof;

         has $dry = False;

         loop {
            given ogg_sync_pageout($!sync, $!page) {
               when -1 {
                  warn "Out of sync!";
                  last;
               }
               when  0 { $dry = True; }
               when  1 { # Synced and returned a page
                  my $serial = ogg_page_serialno($!page);

                  my $stream = do if ogg_page_bos($!page) {
                     %!streams{$serial} = StreamState.new: $serial;
                  } else {
                     %!streams{$serial};
                  }

                  unless $stream {
                     warn "Unknown stream $stream";
                     next;
                  }

                  unless ogg_stream_pagein($stream, $!page) == 0 {
                     die "Can't insert page into stream $serial";
                  }
               }
            } # given ogg_sync_pageout ...

            # try to tease packets out of some stream. fcfs
            for %!streams.values -> $stream {
               my $serial = $stream.serial;
               given ogg_stream_packetout($stream, $!packet) {
                  when -1 { fail "Unable to retrieve packet from stream $serial: missing data (lost sync)" }
                  when  0 { * };
                  when  1 {
                     %!streams{$serial}:delete if $!packet.eos;
                     return PacketData.new(
                        :$serial,
                        :contents(slurp-ptr($!packet.contents-ptr, $!packet.content-size)),
                        :granule-pos($!packet.granule-pos),
                        :bos($!packet.bos),
                        :eos($!packet.eos),
                        :packet-nubmer($!packet.packet-number)
                     );
                  }
               }
            } # for %!streams.values ...

            # how do we deal with an EOS condition that isn't marked?
            # if the input stream is at EOF, we did not return a packet above,
            # and we did not read a page
            last if $!in.eof && $dry;
            
            last unless %!streams; # TODO what happens if EOS isn't set on page?
         } # loop ...
      } # $!mtx.protect ...
   } # method ... 
   
   # Packet seq
   method packets {
      lazy gather {
         take while self.read-packet;
      }
   }
}

class LOGGWriter is export {
   has IO::Handle $.out is required;

   has %!streams;
   has Packet $!packet .= new;
   has Page $!page     .= new;
   has Lock $!mtx      .= new;

   # flush available pages, trying to interleave streams
   method !flush-pages(Bool :$force) {
      my $wet  = True;
      my &read = $force ?? &ogg_stream_flush !! &ogg_stream_pageout;

      for %!streams.values -> $stream {
         while my $r = &read($stream, $!page) {
            my $hdr  = slurp-ptr($!page.header-ptr, $!page.header-len);
            my $body = slurp-ptr($!page.body-ptr, $!page.body-len);

            $!out.write: $hdr;
            $!out.write: $body;
         }
      }

      # TODO: better chaining? not really critical for intended use.
      #`(
      while $wet {
         $wet = False;

         for %!streams.values -> $stream {
            if &read($stream, $!page) {
               $wet ||= True;

               my $hdr  = slurp-ptr($!page.header-ptr, $!page.header-len);
               my $body = slurp-ptr($!page.body-ptr, $!page.body-len);

               $!out.write: $hdr;
               $!out.write: $body;
            }
         }
      }
      )     
   }

   #| Write a packet
   method write-packet(
      Blob[uint8] $data,           #= Packet data
      Int  :$granule-pos = -1,     #= Packet granule position
      Int  :$serial,               #= Stream serial number
      Bool :$eos = False,          #= Is this the last packet in the logical stream?
      Bool :flush($force) = False  #= Force the writing of a page
   ) {
      $!mtx.protect: {
         $!packet.contents = nativecast(Pointer, $data);
         $!packet.content-size = $data.bytes;
         $!packet.eos = $eos;
         $!packet.granule-pos = $granule-pos;

         my $stream = %!streams{$serial} //= StreamState.new: $serial;

         %!streams{$serial}:delete if $eos;
         
         given ogg_stream_packetin($stream, $!packet) {
            when -1 { fail "An error occurred within libOGG" }
            when  0 {
               self!flush-pages :$force;
               True;
            }
         }
      }
   }

   method flush {
      $!mtx.protect: {
         self!flush-pages: :force;
      }
   }
}

multi sub memcpy(Buf $dest, Pointer $src, size_t $n --> Pointer) is native {};
multi sub memcpy(Pointer $dest, Buf $src, size_t $n --> Pointer) is native {};

multi sub memcmp(Buf $s1, Pointer $s2, size_t $n --> int32) is native {};
multi sub memcmp(Pointer $s1, Buf $s2, size_t $n --> int32) is native {};

sub malloc(size_t --> Pointer) is native {};

#| Initialize a sync state
sub ogg_sync_init(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Check error/readiness condition of a SyncState
#| Returns 0 if ready, nonzero if error
sub ogg_sync_check(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Free a SyncState and associated internal memory
sub ogg_sync_destroy(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Sets up a properly-sized buffer for writing.
#| Returns a pointer to the adjusted buffer.
sub ogg_sync_buffer(SyncState $oy, int64 $size --> Pointer[uint8]) is native(lib) is export(:ALL) {};
#| Used to tell the SyncState how many bytes were written into the buffer.
sub ogg_sync_wrote(SyncState $oy, int64 $bytes --> int32) is native(lib) is export(:ALL) {};
#| Takes the data stored in the buffer of the SyncState and inserts it into a page.
#| In an actual decoding loop, this function should be called first to ensure that the buffer is clear.
#| Caution: this function should be called before reading into the buffer to ensure that data does not remain
#| in the SyncState. Failing to do so may result in a memory leak. See example:
#| C<
#|  if (ogg_sync_pageout(&oy, &og) != 1) {
#|	buffer = ogg_sync_buffer(&oy, 8192);
#|	bytes = fread(buffer, 1, 8192, stdin);
#|	ogg_sync_wrote(&oy, bytes);
#| }
#| >
#|
#| Returns -1 if the stream has not yet captured sync
#| Returns 0 if more data is needed
#| Returns 1 if a page was synced and returned.
sub ogg_sync_pageout(SyncState $oy, Page $og --> int32) is native(lib) is export(:ALL) {};
#| Indicates whether the given page is the beginning of the logical bitstream
#| Returns >0 if the page is the beginning of a bitstream
#| Returns =0 if the page is from any other location
sub ogg_page_bos(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Returns the unique serial number for the logical bitstream of this page. Each page contains
#| the serial number for the logical bitstream that it belongs to.
sub ogg_page_serialno(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Initialize a StreamState and allocate memory in preparation for encoding/decoding work.
#| Also assigns the stream a given serial number.
#| Returns 0 if successful, -1 if unsuccessful 
sub ogg_stream_init(StreamState $os, int32 $serialno --> int32) is native(lib) is export(:ALL) {};
#| Frees memory associated with a StreamState, as well as the StreamState itself.
sub ogg_stream_destroy(StreamState $os --> int32) is native(lib) is export(:ALL) {};
#| Add a complete page to the bitstream
#| C<os> pointer to stream state for current logical bitstream
#| C<og> page of data being submitted
#| Returns -1 on failure, 0 success
sub ogg_stream_pagein(StreamState $os, Page $og --> int32) is native(lib) is export(:ALL) {};
#| Assemble a data packet for output to the codec decoding engine.
#| The data has already been submitted to the StreamState and broken into segments.
#| Each successive call returns the next complete packet built from those segments.
#| Typically, this should be called after calling C<ogg_stream_pagein()> to submit a page of
#| data to the bitstream. If the function returns 0, more data is needed and another page should
#| be submitted. A non-zero return value indicates the successful return of a packet.
#| Returns -1 if out of sync, 0 if there is insufficient data, and 1 if a packet was assembled.
sub ogg_stream_packetout(StreamState $os, Packet $op --> int32) is native(lib) is export(:ALL) {};
#| Submits a packet to the bitstream for page encapsulation. After this is called,
#| more packets can be submitted, or pages can be written out.
#| Returns 0 on success, -1 on internal error.
sub ogg_stream_packetin(StreamState $os, Packet $op --> int32) is native(lib) is export(:ALL) {};
#| Forms packets into pages.
#| Typically, this would be called after using C<ogg_stream_packetin()> to submit data packets to the bitstream.
#| Internally, this function assembles the accumulated packet bodies into an ogg page suitable for writing to a stream.
#| This function is typically called in a loop until no more pages are available for writing.
#| The function will only return a page when a "reasonable" amount of packet data is available. Normally, this is appropriate
#| since it limits the overhead of the ogg page headers in the bitstream, and so calling C<ogg_stream_pageout()>
#| after C<ogg_stream_packetin()> should be the common case. Call C<ogg_stream_flush()> if immediate page generation is needed.
#| Doing so may be necessary to limit latency of a bitstream.
#| $og points to a Page to be filled in. Data is owned by libogg.
sub ogg_stream_pageout(StreamState $os, Page $og --> int32) is native(lib) is export(:ALL) {};
#| Forms packets into pages, but allows for a specific spill size to be specificed.
#| In a typical situation, this would be called after C<ogg_stream_packetin()> to submit data packets.
#| This function will return a page when at least four packets have been accumulated and accumulated packet data meets or exceeds
#| the specified number of bytes, and/or when the accumulated packet data meets/exceeds the maximum page size regardless
#| of accumulated packet count.
#| C<ogg_stream_flush()> or C<ogg_stream_flush_fill()> may be called to force page generation if desired.
#| $nfill is the packet data watermark in bytes
sub ogg_stream_pageout_fill(StreamState $os, Page $og, int32 $nfill --> int32) is native(lib) is export(:ALL) {};
#| Forces remaining packets into a page, regardless of size of the page.
#| This should only be used when an undersized page must be flushed in the middle of the stream.
#| This function can also be used to verify that all packets have been flushed. If the return value is zero, all packets have been flushed.
sub ogg_stream_flush(StreamState $os, Page $og --> int32) is native(lib) is export(:ALL) {};
#| Similar to C<ogg_stream_flush()> but allows applications to explicitly request a page spill size.
sub ogg_stream_flush_fill(StreamState $os, Page $og, int32 $nfill --> int32) is native(lib) is export(:ALL) {};

# not used -------
#`(
#| Initalize a buffer
sub oggpack_writeinit(Buffer $b) is native(lib) is export(:ALL) {};
#| Checks the readiness status of a buffer.
#| Returns zero when ready, nonzero when not ready or error.
sub oggpack_writecheck(Buffer $b --> int32) is native(lib) is export(:ALL) {};
#| Reset the contents of a buffer without freeing its memory
sub oggpack_reset(Buffer $b) is native(lib) is export(:ALL) {};
#| Truncate an already written-to buffer
#| Truncates $b to $bits bits
sub oggpack_writetrunc(Buffer $b, int64 $bits) is native(lib) is export(:ALL) {};
#| Pad buffer with zeros to next byte boundary
sub oggpack_writealign(Buffer $b) is native(lib) is export(:ALL) {};
#| Copy up to 32 bits from source to the buffer.
sub oggpack_writecopy(Buffer $b, Pointer[void] $src, int64 $bits) is native(lib) is export(:ALL) {};
#| Clear a buffer and free its memory
sub oggpack_writeclear(Buffer $b) is native(lib) is export(:ALL) {};
#| Prepare a buffer for reading
sub oggpack_readinit(Buffer $b, Pointer[uint8] $buf, int32 $bytes) is native(lib) is export(:ALL) {};
#| Write $bits <= 32 of $value to $b
sub oggpack_write(Buffer $b, uint64 $value, int32 $bits) is native(lib) is export(:ALL) {};
#| Look at a number of $bits <= 32 without advancing
sub oggpack_look(Buffer $b, int32 $bits --> int64) is native(lib) is export(:ALL) {};
#| Look at the next bit without advancing
sub oggpack_look1(Buffer $b --> int64) is native(lib) is export(:ALL) {};
#| Advance $bits
sub oggpack_adv(Buffer $b, int32 $bits) is native(lib) is export(:ALL) {};
#| Advance one bit
sub oggpack_adv1(Buffer $b) is native(lib) is export(:ALL) {};
#| Read (up to 64?) bits from the buffer, advancing the location pointer
sub oggpack_read(Buffer $b, int32 $bits --> int64) is native(lib) is export(:ALL) {};
#| Read one bit, advancing the location pointer
sub oggpack_read1(Buffer $b --> int64) is native(lib) is export(:ALL) {};
#| Return the total number of bytes behind the current access point in the buffer
#| For write-initialized buffers, this is the number of complete bytes written so far.
#| For read-initialized buffers, this is the number of complete bytes that have been read so far.
#| If a byte is partially read, it will be counted as one byte.
sub oggpack_bytes(Buffer $b --> int64) is native(lib) is export(:ALL) {};
#| Return the total number of bits currently in the internal buffer
sub oggpack_bits(Buffer $b --> int64) is native(lib) is export(:ALL) {};
#| Returns a pointer to the data buffer within the buffer structure
sub oggpack_get_buffer(Buffer $b --> Pointer[uint8]) is native(lib) is export(:ALL) {};
#| Free internal storage used by a sync state and reset.
#| Does not free the entire state, just internal storage.
sub ogg_sync_clear(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Reset internal counters of a SyncState
sub ogg_sync_reset(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Synchronize the SyncState to the next Page.
#| Usefull when seeking within a bitstream.
#| Returns <0 the number of bytes skipped within the bitstream.
#| Returns =0 when the page isn't ready and more data is needed. No bytes were skipped.
#| Returns >0 when the page was synced at the current location, with a page length of (return) bytes.
sub ogg_sync_pageseek(SyncState $oy, Page $og --> int64) is native(lib) is export(:ALL) {};
#| Assemts to assemble a raw data packet and return it without advancing decoding
#| This would typically be called speculatively after C<ogg_stream_pagen()> to check the packet
#| contents before handing it off to a codec for decompression. To advance page decoding and remove
#| the packet from the sync structure, call C<ogg_stream_packetout()>.
#| $op is a pointer to the next available packet if any. If Nil, this functions as a simple "is there a packet" check.
#| Returns -1 if no packet is available due lost sync or holes, 0 if there is insufficient data or an
#| internal error occurred, or 1 if a packet is available.
sub ogg_stream_packetpeek(StreamState $os, Packet $op --> int32) is native(lib) is export(:ALL) {};
#| Check readiness of a stream state.
#| Returns 0 if ready, nonzero if was never init'd or an internal error occurred.
sub ogg_stream_check(StreamState $os --> int32) is native(lib) is export(:ALL) {};
#| Clears and frees internal memory used by a StreamState.
#| This is safe to use on the same state repeatedly.
sub ogg_stream_clear(StreamState $os --> int32) is native(lib) is export(:ALL) {};
#| Returns StreamState to its initialize state
sub ogg_stream_reset(StreamState $os --> int32) is native(lib) is export(:ALL) {};
#| Does as C<ogg_stream_reset()> but also sets the serial number
sub ogg_stream_reset_serialno(StreamState $os, int32 $serialno --> int32) is native(lib) is export(:ALL) {};
#| Returns the Page version of the given Page
#| All pages currently have the same version - zero
#| Nonzero return values indicate an error.
sub ogg_page_version(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Indicates whether this page contains packet data which has been continued from
#| the previous page.
#| Returns 1 if there is continued data, 0 if there is not any.
sub ogg_page_continued(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Returns the number of complete packets in the given page.
#| If the leading packet is incomplete (continued from the previous page)
#| but ends on this page, it still counts as one packet.
#| If the page consists of a single packet that began on a previous page and ends
#| on a later page, the packet count will be zero.
sub ogg_page_packets(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Indicates whether the given page is the end of the logical bitstream
#| Returns >0 if the page is at the end
#| Returns =0 if the page is from any other location
sub ogg_page_eos(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Returns the granular position of the packet data at the end of this page.
#| This is useful for tracking location when seeking or decoding.
#| For example, in audio codecs this is the PCM sample number, and in video this is the frame number.
sub ogg_page_granulepos(Page $og --> int64) is native(lib) is export(:ALL) {};
#| Returns the sequential page number.
sub ogg_page_pageno(Page $og --> int64) is native(lib) is export(:ALL) {};
#| Clears memory used by a Packet, without freeing the Packet itself.
sub ogg_packet_clear(Packet $op) is native(lib) is export(:ALL) {};
#| Compute the checksum for a page.
sub ogg_page_checksum_set(Page $og) is native(lib) is export(:ALL) {};

# The following functions are not documented at https://xiph.org/ogg/doc/libogg/reference.html
sub ogg_stream_eos(StreamState $os --> int32) is native(lib) is export(:ALL) {};
sub ogg_stream_iovecin(StreamState $os, IOVec $iov, int32 $count, int64 $eos, int64 $granulepos --> int32) is native(lib) is export(:ALL) {};
)
