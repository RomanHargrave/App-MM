use App::MM::Metadata;

unit class App::MM::Metadata::VorbisComment does Metadata does Iterable is export;

my constant KeyExpr = /<[\x20..\x3C \x3E..\x7D]>+/;

grammar Comment {
   rule  TOP   { <key> '=' <value> }
   token key   { <{KeyExpr}> }
   token value { .* }
}

# ---- class VorbisComment ----

has %!fields;

has $.vendor is readonly;

method delete($k) { %!fields{$k}:delete }

method get($k --> Array) {
   fail "Invalid key" unless $k ~~ KeyExpr;

   return-rw (%!fields{$k} //= []);
}

method exists($k) { %!fields{$k}:exists }

multi method iterator(App::MM::Metadata::VorbisComment:D:) {
   %!fields.iterator;
}

method serialize(--> Blob) {
   my $vendor-buf = $!vendor.encode: 'UTF-8';

   my $data = Buf.allocate: 4 + $vendor-buf.bytes + 4;

   $data.write-uint32: 0, $vendor-buf.bytes;
   $data.splice: 4, $vendor-buf.bytes - 1, $vendor-buf;

   for %!fields.kv -> $name, $values {
      next unless $values;
      for $values.Array -> $value {
         my $pair-buf = "$name=$value".encode: 'UTF-8';
         $data.write-uint32: $data.bytes, $pair-buf.bytes;
         $data.append: $pair-buf;
      }
   }

   $data.write-uint8: $data.bytes, 1;
}

method deserialize(Blob $in) {
   # clear whatever is in the map
   %!fields{$_}:delete for %!fields.keys;

   my $off = 0;

   # were we passed a raw vorbis packet?
   if $in.subbuf(0, 7).decode('UTF8-C8') eq "\x3vorbis" {
      warn 'Adjusting offset for vorbis capture';
      $off += 7;
   }
   
   my $vendor-length = $in.read-uint32:  $off; # + 4 = 4

   $off += 4;
   
   $!vendor = $in.subbuf($off, $vendor-length).decode: 'UTF-8';
   
   $off += $vendor-length;
   
   my $comment-count = $in.read-uint32: $off;

   $off += 4;

   for 1..$comment-count {
      die "Read past end of data (off => $off, data => {$in.bytes})" if $off > $in.bytes;

      my $comment-length = $in.read-uint32: $off;
      my $comment-buf    = $in.subbuf($off + 4, $comment-length).decode: 'UTF-8';
      $off += 4 + $comment-length;
      
      my $comment = Comment.parse: $comment-buf;

      unless $comment {
         warn "Invalid comment: «$comment-buf»";
         next;
      }

      #%!fields{$comment<key>.Str} 
      (%!fields{$comment<key>.Str} //= []).push: $comment<value>.Str;
   }

   my $framing = $in.read-uint8: $off;

   die "Framing bit not set" unless $framing +& 1;
}
