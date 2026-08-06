#!/usr/bin/env ruby
# Generates the bundled factory Keyboard Set Library catalog from the text
# extracted from the official PA700 v1.5 Musical Resources appendix.

require "json"

root = File.expand_path("..", __dir__)
source_path = File.join(root, "tmp/pdfs/pa700-musical-resources.txt")
output_path = File.join(root, "Sources/ArrangerLabCore/Resources/pa700-keyboard-sets.json")
categories = {
  0 => "Piano & EP", 1 => "Organ", 2 => "Guitar", 3 => "Strings",
  4 => "Brass", 5 => "Trumpet", 6 => "Sax & Woodwinds", 7 => "Synth",
  8 => "Ethnic"
}
headings = categories.values.sort_by { |name| -name.length }
keyboard_sets = []

lines = File.readlines(source_path)
start_index = lines.index { |line| line.strip == "Keyboard Set Library" } || abort("Keyboard Set Library section missing")
end_index = lines.index.with_index { |line, index| index > start_index && line.strip == "Sounds" } || abort("Sounds section missing")

lines[(start_index + 1)...end_index].each do |line|
  cursor = 0
  matches = line.to_enum(:scan, /\s{2,}(\d+)\s{2,}(\d+)\s{2,}(\d+)(?=\s{2,}|$)/).map { Regexp.last_match }
  matches.each do |match|
    raw_name = line[cursor...match.begin(0)].strip
    cursor = match.end(0)
    headings.each { |heading| raw_name = raw_name.sub(/^#{Regexp.escape(heading)}\s{10,}/, "") }
    name = raw_name.gsub(/\s+/, " ")
    next if name.empty? || name.start_with?("Keyboard Set") || name.start_with?("CC00")

    msb, lsb, program = match.captures.map(&:to_i)
    next unless msb == 16 && categories.key?(lsb)
    keyboard_sets << {
      id: "factory-keyboard-set-#{msb}-#{lsb}-#{program}",
      displayName: name,
      category: categories.fetch(lsb),
      bankMSB: msb,
      bankLSB: lsb,
      program: program
    }
  end
end

keyboard_sets.sort_by! { |entry| [entry[:bankMSB], entry[:bankLSB], entry[:program]] }
abort "Expected 298 Keyboard Sets, found #{keyboard_sets.length}" unless keyboard_sets.length == 298
abort "Duplicate Keyboard Set address" unless keyboard_sets.map { |entry| [entry[:bankMSB], entry[:bankLSB], entry[:program]] }.uniq.length == keyboard_sets.length

catalog = {
  schemaVersion: 1,
  model: "PA700",
  firmware: "1.5.0",
  source: "Korg PA700 User Manual v1.5, Musical Resources pages 948-952",
  keyboardSets: keyboard_sets
}
File.write(output_path, JSON.pretty_generate(catalog) + "\n")
puts "Wrote #{keyboard_sets.length} Keyboard Sets to #{output_path}"
