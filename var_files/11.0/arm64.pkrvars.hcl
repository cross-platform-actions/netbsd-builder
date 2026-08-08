checksum = "sha512:4d7aa6414549da4453e09fa94758b59d601133cbeaa01ac6c55a819384dd4aea3a1019514f011c4d50ffa4ecf60e3eb21c092017de353c3d3525ce69976270c0"

# 11.0/evbarm-aarch64 gained "Manual pages (HTML)", which moves the X11 sets
# from n to o. It has no 32-bit compatibility set, so unlike amd64 the compiler
# tools stay at the default f.
key_x11_sets = "o"
