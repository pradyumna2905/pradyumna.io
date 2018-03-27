require 'etc'
require 'date'

class PostCreator
  def initialize(toplevel_directory)
    @toplevel_directory = toplevel_directory
  end

  def create
    STDOUT.print 'Please enter post TITLE: '
    title = STDIN.gets.strip

    if title.size == 0
      abort('You must provide a title')
    end

    slug = title.downcase.gsub(/[^A-Za-z0-9 ]/, '').strip.gsub(' ', '-')
    filename =
      "#{@toplevel_directory}/_posts/#{today}-#{slug}.md"

    directory = File.dirname(filename)
    unless Dir.exist?(directory)
      FileUtils.mkdir(directory)
    end

    if File.exist?(filename)
      abort("File already exists: #{filename}")
    end

    open(filename, 'w') do |post|
      post.puts "---"
      post.puts "title: #{title}"
      post.puts "layout: post"
      post.puts "---"
    end

    puts "Created new post at #{filename}"
  end

  private

  def today
    Time.now.strftime("%Y-%m-%d")
  end
end
