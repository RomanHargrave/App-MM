use NativeCall;

#| Raku bindings to libogg
unit module App::MM::Tags::Format::LibOGG is export;

my constant lib = ('ogg', 0);

# Internal?
class IOVec is repr<CStruct> is export(:ALL) {
   has Pointer[void] $.base;
   has size_t $.len;
}

#| Corresponds to C<struct oggpack_buffer>
#| Internal structure for use with oggpack_ subs
class Buffer is repr<CStruct> is export(:ALL) {
   has int64 $.endbyte;
   has int32 $.endbit;

   #| Pointer to data being manipulated
   has Pointer[uint8] $.buffer;

   #| Pointer to mark which data has been read
   has Pointer[uint8] $.ptr;

   #| Size of buffer
   has int64 $.storage;

   method new(--> ::?CLASS) {
      oggpack_writeinit(self);
      self
   }

   method is-ready() {
      oggpack_writecheck(self) == 0;
   }

   method reset() {
      oggpack_reset(self);
   }

   # zero-pad to next byte
   method align() {
      oggpack_writealign(self);
   }
}

#| Corresponds to C<struct ogg_page>
#| Encapsulates data for an ogg page
class Page is repr<CStruct> is export(:ALL) {
   #| Pointer to the header for this page
   has Pointer[uint8] $.header-ptr;

   #| Length of page header in bytes
   has int64 $.header-len;

   #| Pointer to data for this page
   has Pointer[uint8] $.body-ptr;

   #| Length of page data (body) in bytes
   has int64 $.body-len;

   method version() {
      ogg_page_version(self);
   }
   
   method packet-count() {
      ogg_page_packets(self);
   }

   method is-continued() {
      ogg_page_continued(self) == 1;
   }

   method is-bos() {
      ogg_page_bos(self) > 0;
   }

   method is-eos() {
      ogg_page_eos(self) > 0;
   }

   method granule-pos() {
      ogg_page_granulepos(self);
   }

   #| Get the stream serial number for this page
   method serial-number() {
      ogg_page_serialno(self);
   }

   #| Get the page sequence number within the stream
   method number() {
      ogg_page_pageno(self)
   }

   method compute-checksum() {
      ogg_page_checksum_set(self);
   }
}

#| Corresponds to C<struct ogg_stream_state>
#| Tracks encode/decode state of the current logical bitstream
class StreamState is repr<CPointer> is export(:ALL) {
   # this is the computed size of ogg_stream_state according to gcc (Gentoo 10.2.0-r5 p6) 10.2.0
   # this shouldn't ever really change, but who knows - libOGG really needs internal allocators.
   my constant Size = 408;

   method new(int32 $serial-number) {
      my $s = nativecast(StreamState, malloc(Size));
      given ogg_stream_init($s, $serial-number) {
         when 0 { $s }
         default { fail "Could not init {::?CLASS.name}: LibOGG returned $_" }
      }
   }
   
   method ready() {
      ogg_stream_check(self) == 0;
   }
   
   method clear() {
      ogg_stream_clear(self);
   }

   multi method reset() {
      ogg_stream_reset(self);
   }

   multi method reset(int32 $serial-number) {
      ogg_stream_reset_serialno(self, $serial-number);
   }

   method insert-page(Page $p) {
      ogg_stream_pagein(self, $p);
   }
   
   submethod DESTROY() {
      say 'DESTROY StreamState';
      ogg_stream_destroy(self);
   }
}

#| Corresponds to C<struct ogg_packet>
#| Encapsulates the data for a single raw packet of data and is used to transfer
#| data between the ogg framing layer and the handling codec
class Packet is repr<CStruct> is export(:ALL) {
   #| Pointer to the packet's data
   has Pointer[uint8] $.packet;
   #| Size of packet data in bytes
   has int64 $.bytes;
   #| Indicates whether this packet begins a logical bitstream
   #| 1 indicates the first packet, 0 any other.
   has int64 $.bos;
   #| Indicates whether this packet ends a bitstream.
   #| 1 indicates the last packet, 0 any other.
   has int64 $.eos;
   #| A number indicating the position of this packet in the decoded data.
   #| This is the last sample, frame, or other unit of information (granule) that
   #| can be completely decoded from this packet.
   has int64 $.granulepos;
   #| Sequential number of this packet in the ogg bitstream.
   has int64 $.packetno;

   # Extract packet memory into a blob managed by raku
   method Blob(--> Blob[uint8]) {
      with my $buf = Buf.new {
         .reallocate: $.bytes;
      }
      my $buf-ptr = nativecast(Pointer, $buf);
      memcpy($buf-ptr, $.packet, $.bytes);
      $buf;
   }
}

#| Corresponds to C<struct ogg_sync_state>
#| Tracks the synchronization of the current page. 
class SyncState is repr<CStruct> is export(:ALL) {
   #| Pointer to buffered stream data
   has Pointer[uint8] $.data-ptr;
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

   method ready() {
      ogg_sync_check(self) == 0;
   }

   method clear() {
      ogg_sync_clear(self);
   }

   method reset() {
      ogg_sync_reset(self);
   }

   method get-buffer(int32 $len) {
      ogg_sync_buffer(self, $len);
   }

   method notify-write(int32 $written) {
      ogg_sync_wrote(self, $written);
   }

   method take-page(Page $p) {
      ogg_sync_pageout(self, $p);
   }
   
   submethod DESTROY() {
      say 'DESTROY SyncState';
      ogg_sync_destroy(self);
   }
}

#| OGG Container Interface
#| Can be continuously fed an ogg bitstream, and it will
#| track the logical streams within the bitstream.
class OGGStream is export {
   class Stream {
      has StreamState $.state is readonly;
      has $.packets-read is readonly = 0;

      method new(int32 $serial-number) {
         say 'Stream.new';
         my StreamState $state .= new: $serial-number;
         my $x = self.bless(:$state);
         $x;
      }

      method accept(Page $page) {
         given $.state.insert-page: $page {
            say "ogg_stream_pagein $_";
            when -1 {
               die "Failed to accept page {$page.number} from stream {$page.serial-number}";
            }
            when 0 { * }
            default {
               die "Unexpected return value from ogg_stream_pagein: $_";
            }
         }
      }

      #| Retrieve packets
      method packets() {
         my Packet $p = Packet.new;
         lazy gather {
            loop {
               given ogg_stream_packetout($.state, $p) {
                  dd $p;
                  say "ogg_stream_packetout(state, p) = $_";
                  last when 0;
                  take $p.Blob when 1;
                  die 'Out of sync' when -1;
               }
            }
         }
      }
   }

   has %!streams; #= tracks streams that we have seen
   has SyncState $!sync-state .= new;

   method streams() {
      %!streams.values;
   }
   
   # Check pageout on syncstate
   submethod !pageout(Page $p) {
      given ogg_sync_pageout($!sync-state, $p) {
         when 1 {
            # $p is complete, feed it to the stream state
            (%!streams{$p.serial-number} //= Stream.new: $p.serial-number).accept: $p;
         }
         when -1 {
            die "An internal error occorred in libOGG while calling ogg_sync_pageout";
         }
         when 0 { * }
         default {
            die "ogg_sync_pageout returned unexpected value «$_»";
         }
      }
   }

   #| Ingest a buffer into the sync state.
   #| $chunk-size determines the amount of data copied per-iteration.
   #| If C<$in.bytes> is less than or equal to C<$chunk-size>, the function will
   #| complete in a single iteration.
   #| If the buffer size exceeds the chunk size, the number of iterations necessary
   #| to consume the entire input buffer will be taken.
   multi method ingest(Buf[uint8] $in, Int :$chunk-size = 65535) {
      die "SyncState not ready" unless $!sync-state.ready;

      my $in-ptr = nativecast(Pointer[uint8], $in);
      my $off = 0;
      my $page = Page.new; # this will get free'd by raku

      loop {
         my $n = min($in.bytes - $off, $chunk-size);
         last if $n == 0;

         # do a pageout on first iteration to ready-up the SyncState
         self!pageout($page);

         # tell libOGG we want to write as many as $chunk-size bytes
         my $dst = ogg_sync_buffer($!sync-state, $chunk-size);

         # ever see a high-level language do this?
         # copy contents of input buffer (as ptr) into the libOGG buffer
         memcpy($dst, $in-ptr.add($off), $n);

         # tell libOGG how much we actually wrote
         unless ogg_sync_wrote($!sync-state, $n) == 0 {
            die "ogg_sync_wrote reported an error condition while copying";
         };

         $off += $n;
      }

      # do a final pageout in case the final iteration completed a page
      self!pageout($page);
   }

   #| Ingest pages from a handle, in $chunk-size buffers, until the handle is exhausted.
   multi method ingest(IO::Handle $in, Int :$chunk-size = 65535, Bool :$rewind = False) {
      my $start-pos = $in.tell;
      self.ingest: $in.read($chunk-size), :$chunk-size until $in.eof;
      $in.seek: $start-pos if $rewind;
   }
}

sub memcmp(Pointer $s1, Pointer $s2, size_t $n --> int32) is native {};
sub memcpy(Pointer $dest, Pointer $src, size_t $n --> Pointer) is native {};
sub malloc(size_t --> Pointer) is native {};

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

#| Initialize a sync state
sub ogg_sync_init(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Check error/readiness condition of a SyncState
#| Returns 0 if ready, nonzero if error
sub ogg_sync_check(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Free internal storage used by a sync state and reset.
#| Does not free the entire state, just internal storage.
sub ogg_sync_clear(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Free a SyncState and associated internal memory
sub ogg_sync_destroy(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Reset internal counters of a SyncState
sub ogg_sync_reset(SyncState $oy --> int32) is native(lib) is export(:ALL) {};
#| Sets up a properly-sized buffer for writing.
#| Returns a pointer to the adjusted buffer.
sub ogg_sync_buffer(SyncState $oy, int64 $size --> Pointer[uint8]) is native(lib) is export(:ALL) {};
#| Used to tell the SyncState how many bytes were written into the buffer.
sub ogg_sync_wrote(SyncState $oy, int64 $bytes --> int32) is native(lib) is export(:ALL) {};
#| Synchronize the SyncState to the next Page.
#| Usefull when seeking within a bitstream.
#| Returns <0 the number of bytes skipped within the bitstream.
#| Returns =0 when the page isn't ready and more data is needed. No bytes were skipped.
#| Returns >0 when the page was synced at the current location, with a page length of (return) bytes.
sub ogg_sync_pageseek(SyncState $oy, Page $og --> int64) is native(lib) is export(:ALL) {};
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
#| Assemts to assemble a raw data packet and return it without advancing decoding
#| This would typically be called speculatively after C<ogg_stream_pagen()> to check the packet
#| contents before handing it off to a codec for decompression. To advance page decoding and remove
#| the packet from the sync structure, call C<ogg_stream_packetout()>.
#| $op is a pointer to the next available packet if any. If Nil, this functions as a simple "is there a packet" check.
#| Returns -1 if no packet is available due lost sync or holes, 0 if there is insufficient data or an
#| internal error occurred, or 1 if a packet is available.
sub ogg_stream_packetpeek(StreamState $os, Packet $op --> int32) is native(lib) is export(:ALL) {};

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

#| Initialize a StreamState and allocate memory in preparation for encoding/decoding work.
#| Also assigns the stream a given serial number.
#| Returns 0 if successful, -1 if unsuccessful 
sub ogg_stream_init(StreamState $os, int32 $serialno --> int32) is native(lib) is export(:ALL) {};
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
#| Frees memory associated with a StreamState, as well as the StreamState itself.
sub ogg_stream_destroy(StreamState $os --> int32) is native(lib) is export(:ALL) {};

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
#| Indicates whether the given page is the beginning of the logical bitstream
#| Returns >0 if the page is the beginning of a bitstream
#| Returns =0 if the page is from any other location
sub ogg_page_bos(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Indicates whether the given page is the end of the logical bitstream
#| Returns >0 if the page is at the end
#| Returns =0 if the page is from any other location
sub ogg_page_eos(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Returns the granular position of the packet data at the end of this page.
#| This is useful for tracking location when seeking or decoding.
#| For example, in audio codecs this is the PCM sample number, and in video this is the frame number.
sub ogg_page_granulepos(Page $og --> int64) is native(lib) is export(:ALL) {};
#| Returns the unique serial number for the logical bitstream of this page. Each page contains
#| the serial number for the logical bitstream that it belongs to.
sub ogg_page_serialno(Page $og --> int32) is native(lib) is export(:ALL) {};
#| Returns the sequential page number.
sub ogg_page_pageno(Page $og --> int64) is native(lib) is export(:ALL) {};
#| Clears memory used by a Packet, without freeing the Packet itself.
sub ogg_packet_clear(Packet $op) is native(lib) is export(:ALL) {};
#| Compute the checksum for a page.
sub ogg_page_checksum_set(Page $og) is native(lib) is export(:ALL) {};

# The following functions are not documented at https://xiph.org/ogg/doc/libogg/reference.html

sub ogg_stream_eos(StreamState $os --> int32) is native(lib) is export(:ALL) {};
sub ogg_stream_iovecin(StreamState $os, IOVec $iov, int32 $count, int64 $eos, int64 $granulepos --> int32) is native(lib) is export(:ALL) {};
