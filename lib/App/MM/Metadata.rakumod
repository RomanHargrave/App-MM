unit role App::MM::Metadata does Associative is export;

method delete($) { * }
# Must return an RW array 
method get($ --> Array) { * }
method exists($ --> Bool) { * }

method deserialize(Blob) { * }
method serialize(--> Blob) { * }

method from(Blob $in) {
   my $md = ::?CLASS.new;
   $md.deserialize($in);
   $md;
}

method AT-KEY(\key) {
   self.get(key);
}

method EXISTS-KEY(\key) {
   self.exists(key);
}

method DELETE-KEY(\key) {
   self.delete(key);
}
