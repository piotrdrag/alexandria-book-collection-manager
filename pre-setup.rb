# Copyright (C) 2004 Dafydd Harries
#
# Loosely based on pre-setup.rb from rbbr by Masao Mutoh.

basename = "alexandria"
config = Config::CONFIG
podir = srcdir_root + "/po/"

# Create MO files.

Dir.glob("po/*.po") do |file|
    lang = /po\/(.*)\.po/.match(file).to_a[1]
    mo_path_bits = ['data', 'locale', lang, 'LC_MESSAGES']
    mo_path = File.join(mo_path_bits)

    (0 ... mo_path_bits.length).each do |i|
        path = File.join(mo_path_bits[0 .. i])
        puts path
        Dir.mkdir(path) unless FileTest.exists?(path)
    end

    system("msgfmt po/#{lang}.po -o #{mo_path}/#{basename}.mo")
end