#!/usr/bin/env ruby

puts "Tell me the title of your post"
title = gets.strip

# puts "Who are you?"
# author = gets.strip
author = "Paul Wilson"

puts "Post categories?"
categories = gets.strip

date = Time.now.strftime('%Y-%m-%d')
file_suffix = title.downcase.gsub(/\s+/, '-').gsub(/[^a-z0-9-]/, '')

file = "_posts/#{date}-#{file_suffix}.md"

p [title, file_suffix, date, file]

File.open(file, 'w') do |f|
  f.puts "---"
  f.puts "layout: post"
  f.puts "title: #{title}"
  f.puts "date: #{Time.now}"
  f.puts "author: #{author}"
  f.puts "categories: #{categories}"
  f.puts "---"
  f.puts
end

editor = ENV['EDITOR']

exec("#{editor} #{file}") if editor
