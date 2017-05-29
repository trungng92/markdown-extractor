#!/usr/bin/env ruby
# Given a list of files, modifies the links
# so that the relative paths include urls
# and overwrites the files

require 'fileutils'
require 'kramdown'
require 'logger'
require 'set'
require 'uri'

# Base directory where all the files will be copied to
# Note that file structure will be preserved when copied
OUTPUT_DIR = ENV['OUTPUT_DIR']

$logger = Logger.new(STDERR)
$logger.level = Logger::DEBUG

def is_uri_relative uri
    relative = (uri =~ /\A#{URI::regexp}+\z/) == nil
    $logger.debug "URI '#{uri}' is relative? #{relative}"
    return relative
end

# Goes through all the files and XXX
def update_file_uris file, repo
    $logger.debug "Trying to read '#{file}'"
    begin
        markdown_text = File.read(file)
        markdown_tree = Kramdown::Document.new(markdown_text)
        prepend_repo_to_rel_links markdown_tree.root, repo
        File.write(file, markdown_tree.to_kramdown)
    rescue Exception => e
        $logger.warn "Exception happened in '#{file}' in #{FileUtils.pwd} => #{e}"
    end
end

# Private method specific to kramdown to recursively search through the tree
# and grab all urls and images
def prepend_repo_to_rel_links markdown_tree_node, repo
    found_link = false
    case markdown_tree_node.type
    when :a
        attr_name = 'href'
        found_link = true
    when :img
        attr_name = 'src'
        found_link = true
    end
    if found_link && is_uri_relative(markdown_tree_node.attr[attr_name])
        $logger.info "Prepending repo '#{repo}' to link '#{markdown_tree_node.attr[attr_name]}'"
        markdown_tree_node.attr[attr_name].prepend "#{repo}/"
    end
    markdown_tree_node.children.each { |child| prepend_repo_to_rel_links child, repo }
end

def main
    $logger.info "Modifying links in '#{OUTPUT_DIR}'"
    return 0 if OUTPUT_DIR == nil
    Dir.glob("#{OUTPUT_DIR}/*").sort.each do |repo_path|
        next unless File.directory? repo_path
        repo = File.basename repo_path
        $logger.info "Found repo '#{repo}'"
        Dir.glob("#{repo_path}/**/*").sort.each do |file|
            next if File.directory? file
            update_file_uris file, repo
        end
    end
end

main()