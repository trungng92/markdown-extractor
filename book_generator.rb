#!/usr/bin/env ruby
# Tool that reads in files, copies them to an output location
# and generates a README.md and SUMMARY.md file for them based off of udocs' format
#
# Prints logs to stderr
#
# Environment variables:
# GIT_DIR
# OUTPUT_DIR
# PROJECT_ID
#
# Usage:
# ./book_generator.rb file1 file2 file3
#

require 'erb'
require 'fileutils'
require 'kramdown'
require 'logger'
require 'set'

# Location to clone the repos to (if they don't exist)
GIT_DIR = ENV['GIT_DIR']

# Base directory where all the files will be copied to
# Note that file structure will be preserved when copied
OUTPUT_DIR = ENV['OUTPUT_DIR']

# Project under which repos are located
# For github, this will be the user
PROJECT_ID = ENV['PROJECT_ID']

$logger = Logger.new(STDERR)
$logger.level = Logger::DEBUG

# Copies all files provided into OUTPUT_DIR
# and preserves the file structure between copies
def copy_preserved_files file_names
    # Output directory needs to be empty because we crawl through the files in generate_summary_file
    raise 'Cannot copy files because output directory is not empty' unless Dir.entries(OUTPUT_DIR) == ['.', '..']
    $logger.info "Copying files from '#{GIT_DIR}' to '#{OUTPUT_DIR}'"
    file_names.each do |file|
        dirname = "#{OUTPUT_DIR}/#{File.dirname file}"
        FileUtils.mkdir_p dirname

        git_file = "#{GIT_DIR}/#{file}"
        new_file = "#{OUTPUT_DIR}/#{file}"
        $logger.debug "Copying '#{git_file}' to '#{new_file}'"
        # cp doesn't like when you call it on directories so ignore directories
        FileUtils.cp git_file, new_file unless File.directory? git_file
    end
end

def generate_top_readme_file
    $logger.info "Generating README.md"

    base_readme_file = 'README.md'
    project = PROJECT_ID
    erb_readme = ERB.new(File.read('project_readme.md.erb'))
    erb_readme.filename = base_readme_file

    readme_output = erb_readme.result binding
    File.write("#{OUTPUT_DIR}/#{base_readme_file}", readme_output)
end

def generate_summary_file
    $logger.info "Generating SUMMARY.md"
    $logger.debug "Scraping through #{OUTPUT_DIR} for files"
    entries = ''
    Dir.glob("#{OUTPUT_DIR}/**/*").sort.each do |full_file|
        # READMEs and SUMMARY automatically get parsed, so no need to do anything for them
        next if full_file.downcase.include?('readme') || full_file.downcase.include?('summary')

        relative_file = full_file.sub("#{OUTPUT_DIR}/", '')
        dir = File.dirname(relative_file)
        depth = relative_file.split(File::SEPARATOR).length
        file = File.basename(relative_file)
        $logger.debug "File '#{relative_file}' has depth #{depth}"

        # I'm going to assume that everything that Dir.glob found is either a file or a directory
        indentations = "    " * (depth - 1)
        entries += "#{indentations}* [#{file}](#{dir}/#{file})\n"
    end

    base_summary_file = 'SUMMARY.md'
    erb_summary = ERB.new(File.read('project_summary.md.erb'))
    erb_summary.filename = base_summary_file

    summary_output = erb_summary.result binding
    File.write("#{OUTPUT_DIR}/#{base_summary_file}", summary_output)
end

def main
    file_names = ARGV
    copy_preserved_files file_names
    generate_top_readme_file
    generate_summary_file
end

main()