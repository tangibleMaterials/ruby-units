require 'mkmf'

# Check for Ragel
ragel = find_executable('ragel')
unless ragel
  abort "Ragel is required to build this extension. Please install ragel."
end

# Generate the C file from Ragel source
puts "Generating C code from Ragel grammar..."
system("ragel -C #{__dir__}/units_parser.rl -o #{__dir__}/units_parser.c")

unless File.exist?("#{__dir__}/units_parser.c")
  abort "Failed to generate C code from Ragel grammar"
end

# Standard Ruby extension configuration
extension_name = 'units_parser'
dir_config(extension_name)

# Create the Makefile
create_makefile("units_parser/units_parser")