#!/usr/bin/env raku

# Based on the pdf-raku project's Base64::Native build

class Build {
   need LibraryMake;
   
   method make(Str $dir, Str $dest, IO() :$libname!) {
      my %vars = LibraryMake::get-vars($dest);
      %vars<LIB_NAME> = ~ $*VM.platform-library-name: $libname;
      %vars<MAKE> = 'make' if Rakudo::Internals.IS-WIN; # lol windows
      mkdir($dest);
      LibraryMake::process-makefile($dir, %vars);
      shell(%vars<MAKE>);
   }
   
   method build(Str $wkdir) {
      .IO.mkdir with my $dst = 'resources/lib';
      self.make($wkdir, $dst, :libname<ogg_crc32>);
      True;
   }
}

sub MAIN(Str $working-dir = '.') {
   Build.new.build($working-dir);
}
