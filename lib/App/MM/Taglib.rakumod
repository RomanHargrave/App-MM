use NativeCall;

unit module App::MM::Taglib;

my constant taglib = ('tag', 0);

#| Equivalent to TagLib_File_Type
enum FileType (
   MPEG      => 0,
   OggVorbis => 1,
   FLAC      => 2,
   MPC       => 3,
   OggFlac   => 4,
   WavPack   => 5,
   Speex     => 6,
   TrueAudio => 7,
   MP4       => 8,
   ASF       => 9
);

class Tag is repr<CStruct> is export(:ALL) {
   has int32 $!dummy;

   method title(--> Str) {
      return-rw Proxy.new(
         FETCH => sub ($ --> Str) {
            taglib-tag-title(self).deref;
         },
         STORE => sub ($, Str $s --> Str) {
            taglib-tag-set-title(self, $s);
            $s;
         }
      );
   }

   method artist(--> Str) {
      return-rw Proxy.new(
         FETCH => sub ($, --> Str) {
            taglib-tag-artist(self).deref;
         },
         STORE => sub ($, Str $s --> Str) {
            taglib-tag-set-artist(self, $s);
            $s;
         }
      );
   }

   method album(--> Str) {
      return-rw Proxy.new(
         FETCH => sub ($, --> Str) {
            taglib-tag-album(self).deref;
         },
         STORE => sub ($, Str $s --> Str) {
            taglib-tag-set-album(self, $s);
            $s;
         }
      );
   }

   method comment(--> Str) {
      return-rw Proxy.new(
         FETCH => sub ($, --> Str) {
            taglib-tag-comment(self).deref;
         },
         STORE => sub ($, Str $s --> Str) {
            taglib-tag-set-comment(self, $s);
            $s;
         }
      );
   }

   method genre(--> Str) {
      return-rw Proxy.new(
         FETCH => sub ($, --> Str) {
            taglib-tag-genre(self).deref;
         },
         STORE => sub ($, Str $s --> Str) {
            taglib-tag-set-genre(self, $s);
            $s;
         }
      );
   }

   method year(--> Int) {
      return-rw Proxy.new(
         FETCH => sub ($, --> Int) {
            taglib-tag-year(self);
         },
         STORE => sub ($, uint32 $i --> Int) {
            taglib-tag-set-year(self, $i);
            $i;
         }
      );
   }

   method track(--> Int) {
      return-rw Proxy.new(
         FETCH => sub ($, --> Int) {
            taglib-tag-track(self);
         },
         STORE => sub ($, uint32 $i --> Int) {
            taglib-tag-set-track(self, $i);
            $i;
         }
      );
   }
}

class AudioProperties is repr<CStruct> is export(:ALL) {
   has int32 $!dummy;

   #| Audio length, in seconds
   method length(--> Int) {
      taglib-audioproperties-length(self);
   }

   #| Audio bitrate, in kb/s
   method bitrate(--> Int) {
      taglib-audioproperties-bitrate(self);
   }

   #| Audio sample rate, in Hz
   method sample-rate(--> Int) {
      taglib-audioproperties-samplerate(self);
   }

   #| Channel count
   method channels(--> Int) {
      taglib-audioproperties-channels(self);
   }
}

#| A TagLib File object. Represents an audio file.
class File is repr<CStruct> is export {
   has int32 $!dummy;

   #| Is this file valid (e.g. has readable tag data)?
   method is-valid(--> Bool) {
      taglib-file-is-valid(self);
   }
   
   #| Retrieve the audioproperties struct for this file
   #| Note that the retrieved structure has its memory managed by taglib,
   #| And will be freed when its corresponding file is freed
   method audioproperties(--> AudioProperties) {
      taglib-file-audioproperties(self);
   }

   method length(--> Int) {
      self.audioproperties.length;
   }

   method bitrate(--> Int) {
      self.audioproperties.bitrate;
   }

   method sample-rate(--> Int) {
      self.audioproperties.sample-rate;
   }

   method channels(--> Int) {
      self.audioproperties.channels;
   }

   #| Retrieve the tag struct for this file
   #| Note that the retrieved structure has its memory managed by taglib,
   #| And will be freed when its corresponding file is freed
   method tag-handle(--> Tag) {
      taglib-file-tag(self);
   }

   multi method tag('title' --> Str) { self.tag-handle.title; }
   multi method tag('artist' --> Str) { self.tag-handle.artlst; }
   multi method tag('album' --> Str) { self.tag-handle.album; }
   multi method tag('comment' --> Str) { self.tag-handle.comment; }
   multi method tag('genre' --> Str) { self.tag-handle.genre; }
   multi method tag('year' --> Str) { self.tag-handle.year.?Str; }
   multi method tag('track' --> Str) { self.tag-handle.track.?Str; }
   multi method tag(Str $what --> Str) { Nil }

   method postcircumfix:<[ ]>(Str $what) { self.tag: $what; }
   
   #| Save the file
   method save() {
      taglib-file-save(self);
   }
   
   submethod DESTROY {
      taglib-file-free(self);
      taglib-tag-free-strings(); # god this is not how memory management should work
   }

   multi sub open(Str $file) {
      taglib-file-new($file);
   }

   multi sub open(Str $file, FileType $type) {
      taglib-file-new-type($file, $type.Int);
   }
}

=begin pod
=head2 File Subs
These correspond to the taglib_file_ family of functions, and are used to interact with File structures.
=end pod

#| Create a taglib file based on filename. Taglib will try to guess the file type.
sub taglib-file-new(
   Str $filename
   --> File
) is native(taglib) is symbol<taglib_file_new> is export(:ALL) {}

#| Create a taglib file based on filename. Taglib will use the specified file type.
sub taglib-file-new-type(
   Str $filename,
   uint8 $type
   --> File
) is native(taglib) is symbol<taglib_file_new_type> is export(:ALL) {}

#| Close and free the file
sub taglib-file-free(
   File $file
) is native(taglib) is symbol<taglib_file_free> is export(:ALL) {}

#| Returns true if the file is open and readable and valid information was found
sub taglib-file-is-valid(
   File $file
   --> Bool
) is native(taglib) is symbol<taglib_file_is_valid> is export(:ALL) {}

#| Returns the tag associated with the file.
sub taglib-file-tag(
   File $file
   --> Tag
) is native(taglib) is symbol<taglib_file_tag> is export(:ALL) {}

#| Get audioproperties associated with file
sub taglib-file-audioproperties(
   File $file
   --> AudioProperties
) is native(taglib) is symbol<taglib_file_audioproperties> is export(:ALL) {}

#| Save a file
sub taglib-file-save(
   File $file
   --> Bool
) is native(taglib) is symbol<taglib_file_save> is export(:ALL) {}

=begin pod
=head2 Tag Subs
These correspond to the taglib_tag_ family of functions and are used for interacting with Tag
structures.
=end pod

#| Get the title from a tag
sub taglib-tag-title(
   Tag $tag
   --> Pointer[Str]
) is native(taglib) is symbol<taglib_tag_title> is export(:ALL) {}

#| Set tag title
sub taglib-tag-set-title(
   Tag $tag,
   Str $title
) is native(taglib) is symbol<taglib_tag_set_title> is export(:ALL) {}

#| Get the artist from a tag
sub taglib-tag-artist(
   Tag $tag
   --> Pointer[Str]
) is native(taglib) is symbol<taglib_tag_artist> is export(:ALL) {}

#| Set artist tag
sub taglib-tag-set-artist(
   Tag $tag,
   Str $artist
) is native(taglib) is symbol<taglib_tag_artist> is export(:ALL) {}

#| Get the album from a tag
sub taglib-tag-album(
   Tag $tag
   --> Pointer[Str]
) is native(taglib) is symbol<taglib_tag_album> is export(:ALL) {}

#| Set album tag
sub taglib-tag-set-album(
   Tag $tag,
   Str $album
) is native(taglib) is symbol<taglib_tag_set_album> is export(:ALL) {}

#| Get the comment from a tag
sub taglib-tag-comment(
   Tag $tag
   --> Pointer[Str]
) is native(taglib) is symbol<taglib_tag_comment> is export(:ALL) {}

#| Set tag comment
sub taglib-tag-set-comment(
   Tag $tag,
   Str $comment
) is native(taglib) is symbol<taglib_tag_set_comment> is export(:ALL) {}

#| Get the genre from a tag
sub taglib-tag-genre(
   Tag $tag
   --> Pointer[Str]
) is native(taglib) is symbol<taglib_tag_genre> is export(:ALL) {}

#| Set genre tag
sub taglib-tag-set-genre(
   Tag $tag,
   Str $genre
) is native(taglib) is symbol<taglib_tag_set_genre> is export(:ALL) {}

#| Get the year from a tag
sub taglib-tag-year(
   Tag $tag
   --> uint32
) is native(taglib) is symbol<taglib_tag_year> is export(:ALL) {}

#| Set year tag
sub taglib-tag-set-year(
   Tag $tag,
   uint32 $year
) is native(taglib) is symbol<taglib_tag_set_year> is export(:ALL) {}

#| Get the track number from a tag
sub taglib-tag-track(
   Tag $tag
   --> uint32
) is native(taglib) is symbol<taglib_tag_track> is export(:ALL) {}

#| Set track tag
sub taglib-tag-set-track(
   Tag $tag,
   uint32 $track
) is native(taglib) is symbol<taglib_tag_set_track> is export(:ALL) {}

#| This is just a bad approach
sub taglib-tag-free-strings() is native(taglib) is symbol<taglib_tag_free_strings> is export(:ALL) {}

=begin pod
=head2 Audio Properties Subs
These correspond to the taglib_audioproperties_ family of functions
=end pod

#| Audio length in seconds
sub taglib-audioproperties-length(
   AudioProperties $audioProperties
   --> uint32
) is native(taglib) is symbol<taglib_audioproperties_length> is export(:ALL) {}

#| Audio bitrate in kb/s
sub taglib-audioproperties-bitrate(
   AudioProperties $audioProperties
   --> uint32
) is native(taglib) is symbol<taglib_audioproperties_bitrate> is export(:ALL) {}

#| Audio sample rate in Hz
sub taglib-audioproperties-samplerate(
   AudioProperties $audioProperties
   --> uint32
) is native(taglib) is symbol<taglib_audioproperties_samplerate> is export(:ALL) {}

#| Number of channels
sub taglib-audioproperties-channels(
   AudioProperties $audioProperties
   --> uint32
) is native(taglib) is symbol<taglib_audioproperties_channels> is export(:ALL) {}


sub MAIN(*@files) is export(:MAIN) {
   for @files {
      
   }
}
