require "http/client"
require "lexbor"
require "option_parser"
require "file_utils"

def grab_file(dest : String, url : String) : String
  dest = Path[dest]
  if url.starts_with?("./pics")
    download_file(dest, url)
    url = url.gsub("./pics", "@/pics")
    return url
  elsif url.starts_with?("https://novalug.org/pics")
    download_file(dest, url)
    url = url.gsub("https://novalug.org/pics", "@/pics")
    return url
  end
  url
end

def download_file(dest : Path, url : String)
  url = url.gsub("./", "https://novalug.org/")
  filename = Path[dest, url.split('/').last]
  response = HTTP::Client.get(url)
  puts "Downloading #{url} to #{filename}"
  HTTP::Client.get(url) do |response|
    response.status_code  # => 200
    File.open(filename, "wb") do |file|
      IO.copy(response.body_io, file)
    end
  end
end

def write_entry(dest : String, pic_no : Number, text : String)
  file_name = "novalug_pic_#{pic_no}.md"
  path = Path[dest, file_name]
  puts "Writing #{path}"
  md_file = File.open(path, "w")
  md_file.puts "+++"
  md_file.puts "+++"
  md_file.puts text
  md_file.close()
end

class Converter
  @text : String = ""
  @pic_no : Int32 = 0

  def convert(dest : String, node : Lexbor::Node)
    node.children.each do |tag|
      if tag.is_tag__text?
        @text = @text + tag.tag_text
      elsif tag.is_tag_a?
        url = grab_file(dest, tag["href"])
        link = tag.inner_text
        puts "adding link to #{url}"
        @text = @text + "[#{link}](#{url})"
      elsif tag.is_tag_img?
        url = grab_file(dest, tag["src"])
        link = tag["alt"]
        puts "adding image to #{url}"
        @text = @text + "![#{link}](#{url})"
      elsif tag.is_tag_br?
        @text = @text + "\n\n"
      elsif tag.is_tag_hr?
        @pic_no = @pic_no + 1
        write_entry(dest, @pic_no, @text)
        @text = ""
      else
        self.convert(dest, tag)
      end
    end
  end

  def complete(dest : String)
    @pic_no = @pic_no + 1
    write_entry(dest, @pic_no, @text)
  end
end

destination : String? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: presentation [arguments]"
  parser.on("-d DEST", "--destination=DEST", "Distination directory for zola markdown files") do |dest| 
    destination = dest 
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

if destination.nil?
  raise "Distination must be give"
end

url = "https://novalug.org/pics.html"
response = HTTP::Client.get(url)
lexbor = Lexbor::Parser.new(response.body.to_s)
pic_no = 0
text = ""
selector = "body > div:nth-child(1) > div:nth-child(1) > div:nth-child(3)"
html = lexbor.css(selector)
converter = Converter.new
html.each do |tag|
  converter.convert(destination.not_nil!, tag)
end
converter.complete(destination.not_nil!)
