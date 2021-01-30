use v6;

use Red:api<2>;

unit class BeetsDB;

has $.db-file where *.IO.f;

model AlbumAttribute is table<album_attributes> {
   has Int $.id is serial;
   has Album $.album is referencing { .id };
   has Str $.key is column;
   has Str $.value is column;
}

model Album is table<albums> {
   has Int $.id is serial;
   has Int $.disctotal is column;
   has Str $.albumstatus is column;
   has Int $.month is column;
   has Int $.original_day is column;
   has Str $.albumartist is column;
   has Int $.year is column;
   has Str $.albumdisambig is column;
   has Str $.albumartist_sort is column;
   has Str $.album is column;
   has Str $.asin is column;
   has Str $.script is column;
   has Str $.mb_albumid is column;
   has Str $.label is column;
   has Real $.rg_album_gain is column;
   has Str $.mb_releasegroupid is column;
   has Str $.artpath is column;
   has Real $.rg_album_peak is column;
   has Str $.albumartist_credit is column;
   has Str $.catalognum is column;
   has Int $.original_month is column;
   has Int $.comp is column;
   has Str $.genre is column;
   has Int $.day is column;
   has Int $.original_year is column;
   has Str $.language is column;
   has Str $.mb_albumartistid is column;
   has Str $.country is column;
   has Str $.albumtype is column;
   has Str $.style is column;
   has Int $.discogs_albumid is column;
   has Int $.discogs_artistid is column;
   has Int $.discogs_labelid is column;
   has Str $.releasegroupdisambig is column;
   has Real $.r128_album_gain is column;
   has DateTime $.added is column {
      :type<int>,
      :inflate{ DateTime.new($_) },
      :deflate{ .posix },
   };
}

model ItemAttributes is table<item_attributes> {
}

model Item is table<items> {
   has Int $.id is serial;
   has Str $.lyrics is column;
   has Str $.disctitle is column;
   has Int $.month is column;
   has Int $.channels is column;
   has Int $.disc is column;
   has Str $.mb_trackid is column;
}

=begin pod
