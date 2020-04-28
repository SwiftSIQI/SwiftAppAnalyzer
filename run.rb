require 'rainbow/refinement'
require 'zip'
require 'byebug'
require 'plist'
require 'fileutils'
require 'csv'

using Rainbow

dir_name = File.expand_path ARGV[0]

unless File.exist?(dir_name)
  puts "#{dir_name} is not exist!".red
end

unless File.directory?(dir_name)
  puts "#{dir_name} is not a directory!".red
end

final_result = []

# 查找目录内部带有 ipa 的文件
ipa_files = Dir.entries(dir_name).select { |entry| File.extname(entry) == '.ipa'}.map { |name| File.join(dir_name, name)}
total_count = ipa_files.length
current_index = 0

# 解决 zip 乱码问题
Zip.force_entry_names_encoding = 'UTF-8'

ipa_files.each do |path|
  ipa_name = File.basename(path)
  zip_file = Zip::File.open(path)
  # 先直接简单扫一下，看是否包含 swift，如果包含，直接记录下来
  swift_framework_entries = zip_file.glob('Payload/*.app/Frameworks/libswift*')
  unless swift_framework_entries.empty?
    final_result.push({
      name: ipa_name,
      used: true,
      details: swift_framework_entries.map(&:name),
    })
    current_index += 1
    puts "#{current_index}/#{total_count}, #{ipa_name} result: true".green
    next
  end
  # 如果不包含，先找一下 plist 文件
  info_plist_entry = zip_file.glob('Payload/*.app/Info.plist').first

  temp_dir = File.join('temp', ipa_name)
  info_plist_path = File.join(temp_dir, 'Info.plist')

  FileUtils.mkdir_p(temp_dir)
  zip_file.extract(info_plist_entry, info_plist_path) unless File.exist?(info_plist_path)
  exec_name = Plist.parse_xml(info_plist_path)['CFBundleExecutable']

  exec_file_entry = zip_file.glob("Payload/*.app/#{exec_name}").first
  exec_file_path = File.join(temp_dir, File.basename(exec_file_entry.name.force_encoding('UTF-8')))
  zip_file.extract(exec_file_entry, exec_file_path) unless File.exist?(exec_file_path)

  otool_result = `otool -L '#{exec_file_path}' | grep swift`

  current_index += 1
  if otool_result.empty? 
    final_result.push({
      name: ipa_name,
      used: false,
      details: [],
    })
    puts "#{current_index}/#{total_count}, #{ipa_name} result: false".yellow
  else
    final_result.push({
      name: ipa_name,
      used: true,
      details: otool_result.split,
    })
    puts "#{current_index}/#{total_count}, #{ipa_name} otool result: true".green
  end
end
puts ''
puts "app used swift: #{final_result.length} / #{total_count}"

CSV.open "temp/result.csv", "w" do |csv|
  csv << ['name', 'used', 'details']
  final_result.each do |result|
    csv << [result[:name], result[:used], result[:details].join(",")]
  end
end