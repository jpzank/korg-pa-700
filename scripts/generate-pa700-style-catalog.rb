#!/usr/bin/env ruby
# Generates the bundled factory Style catalog from the text extracted from the
# official PA700 v1.5 Musical Resources appendix (pages 942-947).

require "json"

root = File.expand_path("..", __dir__)
source_path = File.join(root, "tmp/pdfs/pa700-musical-resources.txt")
output_path = File.join(root, "Sources/ArrangerLabCore/Resources/pa700-styles.json")
categories = {
  0 => "Pop", 1 => "Ballad", 2 => "Ballroom", 3 => "Dance",
  4 => "Rock", 5 => "Country", 6 => "Latin", 7 => "Latin Dance",
  8 => "Jazz", 9 => "Movie & Show", 10 => "Funk & Blues", 11 => "World"
}
headings = categories.values.sort_by { |name| -name.length }
styles = []

File.readlines(source_path).first(240).each do |line|
  cursor = 0
  matches = line.to_enum(:scan, /\s{2,}(\d+)\s{2,}(\d+)\s{2,}(\d+)(?=\s{2,}|$)/).map { Regexp.last_match }
  matches.each do |match|
    raw_name = line[cursor...match.begin(0)].strip
    cursor = match.end(0)
    headings.each { |heading| raw_name = raw_name.sub(/^#{Regexp.escape(heading)}\s{10,}/, "") }
    name = raw_name.gsub(/\s+/, " ")
    next if name.empty? || name.start_with?("Style") || name.start_with?("CC00")

    msb, lsb, program = match.captures.map(&:to_i)
    styles << {
      id: "factory-style-#{msb}-#{lsb}-#{program}",
      displayName: name,
      category: categories.fetch(lsb),
      bankMSB: msb,
      bankLSB: lsb,
      program: program
    }
  end
end

styles.sort_by! { |style| [style[:bankMSB], style[:bankLSB], style[:program]] }
abort "Expected 379 Styles, found #{styles.length}" unless styles.length == 379
abort "Duplicate Style address" unless styles.map { |style| [style[:bankMSB], style[:bankLSB], style[:program]] }.uniq.length == styles.length

catalog = {
  schemaVersion: 1,
  model: "PA700",
  firmware: "1.5.0",
  source: "Korg PA700 User Manual v1.5, Musical Resources pages 942-947",
  styles: styles
}
File.write(output_path, JSON.pretty_generate(catalog) + "\n")
puts "Wrote #{styles.length} Styles to #{output_path}"
