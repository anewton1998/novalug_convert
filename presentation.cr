require "http/client"
require "lexbor"
require "option_parser"
require "file_utils"

class Presentation
  @date : String? = "1970-01-01"
  @presenters : Array(String) = [] of String
  @title : String = ""
  @summary : String? = nil
  @other_links : Array(String) = [] of String
  @materials : Array(String) = [] of String
  @video : String? = nil

  def date=(html : Lexbor::Node)
    date = html.inner_text
    if date != ""
      date = date.gsub(".", "-")
      if date.count('-') == 1
        date = date + "-01"
      end
      @date = date
    else
      @date = "1970-01-01"
    end
  end

  def date
    @date
  end

  def presenters=(html : Lexbor::Node)
    @presenters = to_md_list(html)
  end

  def presenters
    @presenters
  end

  def title=(html : Lexbor::Node)
    @title = html.inner_text.gsub("\n", " ")
  end

  def title
    @title
  end

  def summary=(html : Lexbor::Node)
    html.children.each do |child|
      if child.is_tag_img? && child["title"]?
        @summary = child["title"].gsub("\n", " ")
      end
    end
  end

  def summary
    @summary
  end

  def other_links=(html : Lexbor::Node)
    html.children.each do |child|
      if child.is_tag_a?
        link_text = child.inner_text
        href = child["href"]
        @other_links << "[#{link_text}](#{href})"
      end
    end
  end

  def other_links
    @other_links
  end

  def materials=(html : Lexbor::Node)
    html.children.each do |child|
      if child.is_tag_a?
        link_text = child.inner_text
        href = child["href"]
        @materials << "[#{link_text}](#{href})"
      end
    end
  end

  def materials
    @materials
  end
  
  def video=(html : Lexbor::Node)
    html.children.each do |child|
      if child.is_tag_a?
        link_text = child.inner_text
        href = child["href"]
        @video = "[#{link_text}](#{href})" if !href.empty?
      end
    end
  end

  def video 
    @video 
  end

end

def to_md_list(node : Lexbor::Node) : Array(String)
  list = Array(String).new
  node.children.each do |child|
    if child.is_text?
      child_text = child.tag_text.gsub("&amp;", "").gsub("&", "").gsub("\u00A0", " ").strip().split(/, | \/ /)
      child_text.reject!(&.empty?)
      list.concat(child_text)
    elsif child.is_tag_a?
      presenter = child.inner_text
      link = child["href"]
      list << "[#{presenter}](#{link})"
    end
  end
  if list.size == 3 && list[1] == "of"
    list = ["#{list[0]} of #{list[2]}"]
  end
  list
end

def parse_html_table(url)
  # Fetch the HTML content
  response = HTTP::Client.get(url)

  # Check for successful response
  if response.status_code == 200
    lexbor = Lexbor::Parser.new(response.body.to_s)

    # Define table selector 
    table_selector = "body > div:nth-child(1) > div:nth-child(1) > div:nth-child(3) > table:nth-child(5) > tbody tr"

    presentations = Array(Presentation).new
    rowspan = false
    table_data = lexbor.css(table_selector).map do |tr|
      presentation = Presentation.new
      td = tr.css("td")
      if td.size == 5
        presentation.date = td[0]
        presentation.title = td[1]
        presentation.summary = td[1]
        presentation.presenters = td[2]
        presentation.materials = td[3]
        presentation.video = td[4]
        if td[0]["rowspan"]?
          rowspan = true
        else
          rowspan = false
        end
        presentations << presentation
      elsif td.size == 4 && rowspan
        presentation.title = td[0]
        presentation.summary = td[0]
        presentation.presenters = td[1]
        presentation.materials = td[2]
        presentation.video = td[3]
        rowspan = false
        presentations << presentation
      elsif td.size == 4
        presentation.date = td[0]
        presentation.title = td[1]
        presentation.summary = td[1]
        presentation.presenters = td[2]
        presentation.materials = td[3]
        presentations << presentation
      end
    end

    return presentations
  else
    raise "Failed to fetch URL: #{url}"
  end
end

def write_presentations(dest : String, presentations : Array(Presentation))
  puts "Writing to #{dest}."
  raise "Not a directory" if !File.info(dest).directory?
  presentations.each do |preso|
    safe_title = preso.title.gsub(/[^\w*]/, '_')
    file_base = "#{safe_title}--#{preso.date}"
    puts "file base #{file_base}"
    directory = Path[dest, file_base]
    FileUtils.mkdir(directory)
    md_file = File.open(Path[directory, "#{file_base}.md"], "w")
    md_file.puts "+++"
    md_file.puts "# this is an auto-converted file"
    md_file.puts %(title = "#{preso.title}")
    md_file.puts %(date = "#{preso.date}")
    md_file.puts "+++"
    md_file.puts "#{preso.summary}\n\n" if preso.summary != nil
    md_file.puts "Presenter(s): #{preso.presenters.join(", ")}\n\n" if !preso.presenters.empty?
    if !preso.other_links.empty?
      md_file.puts "Other Links:"
      preso.other_links.each do |link|
        md_file.puts "* #{link}"
      end
      md_file.puts
    end
    if !preso.materials.empty?
      materials = grab_materials(directory, file_base, preso.materials)
      md_file.puts "Materials:"
      materials.each do |link|
        md_file.puts "* #{link}"
      end
      md_file.puts
    end
    md_file.puts "Video: #{preso.video}" if preso.video != nil
  end
end

def grab_materials(dest : Path, file_base : String, materials : Array(String)) : Array(String)
  new_links = Array(String).new
  materials.each do |m|
    link = parse_markdown_link(m)
    if !link.nil?
      url = link[:url].not_nil!
      text = link[:text].not_nil!
      if url.starts_with?("./docs")
        download_file(dest, url)
        url = url.gsub("./docs", "@/presentations/#{file_base}")
        new_links << "[#{text}](#{url})"
      elsif url.starts_with?("https://novalug.org/docs")
        download_file(dest, url)
        url = url.gsub("https://novalug.org/docs", "@/presentations/#{file_base}")
        new_links << "[#{text}](#{url})"
      else
        new_links << m
      end
    end  
  end
  new_links
end

def parse_markdown_link(markdown_text)
  match = /\[([^\]]*)\]\(([^\)]*)\)/.match(markdown_text)
  return nil if match.nil?

  text, url = match.captures

  # Return a Hash containing link information
  { text: text, url: url }
end

def download_file(dest : Path, url : String)
  url = url.gsub("./", "https://novalug.org/")
  filename = Path[dest, url.split('/').last]
  response = HTTP::Client.get(url)
  puts "Downloading #{url} to #{filename}"
  HTTP::Client.get("http://www.example.com") do |response|
    response.status_code  # => 200
    File.open(filename, "wb") do |file|
      IO.copy(response.body_io, file)
    end
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

url = "https://novalug.org/presentations.html"
presentations = parse_html_table(url)

write_presentations(destination.not_nil!, presentations)

# if presentations
#   puts "Successfully parsed table data:"
#   presentations.each do |preso|
#     puts "+++"
#     puts "Date: #{preso.date}"
#     puts "Title: #{preso.title}"
#     puts "Presenters: #{preso.presenters.join(", ")}" if !preso.presenters.empty?
#     puts "Summary: #{preso.summary}" if preso.summary != nil
#     if !preso.other_links.empty?
#       puts "Other Links:"
#       preso.other_links.each do |link|
#         puts "* #{link}"
#       end
#     end
#     if !preso.materials.empty?
#       puts "Materials:"
#       preso.materials.each do |link|
#         puts "* #{link}"
#       end
#     end
#     puts "Video: #{preso.video}" if preso.video != nil
#   end
# else
#   puts "Error: Failed to parse table."
# end

