checksum = "sha512:2b8f15ea6f4012ef962ffd054bead5dcb1c2233ebdf6d41d23be066b2a9e19978378b0f7f588ed6ab9cde8a5ec618ea560e800fe762309aa28bc36b6480e2734"

# 11.0/amd64 has two more sets above these than 10.x did -- "Base 32-bit
# compatibility libraries" and "Manual pages (HTML)" -- which moves the
# compiler tools from f to g and the X11 sets from n to p.
key_compiler_tools = "g"
key_x11_sets = "p"
