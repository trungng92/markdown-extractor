#!/usr/bin/env ruby
# Tool to pull down a list of git repos from a project and
# recursively analyze the readme and
# determine all the local files that it links to
#
# Prints logs to stderr
# Prints referenced local files (delimited by space) to stdout
#
# Environment variables:
# GIT_DIR = ENV['GIT_DIR']
# BASE_GIT_URL = ENV['BASE_GIT_URL']
# BASE_GIT_PORT = ENV['BASE_GIT_PORT']
# GIT_USER = ENV['GIT_USER']
# GIT_PASSWORD = ENV['GIT_PASSWORD']
# PROJECT_ID = ENV['PROJECT_ID']
#
# Usage:
# ./markdown_extractor.rb
#

# TODO: Add a second parser that can generate the gitbook style of markdown SUMMARY.md

require 'fileutils'
require 'json'
require 'kramdown'
require 'logger'
require 'openssl'
require 'net/http'
require 'set'
require 'uri'

# Location to clone the repos to (if they don't exist)
GIT_DIR = ENV['GIT_DIR']
# Base url to access git projects/repos
BASE_GIT_URL = ENV['BASE_GIT_URL']
BASE_GIT_PORT = ENV['BASE_GIT_PORT']

GIT_USER = ENV['GIT_USER']
GIT_PASSWORD = ENV['GIT_PASSWORD']
# Project under which repos are located
# For github, this will be the user
PROJECT_ID = ENV['PROJECT_ID']

$logger = Logger.new(STDERR)
$logger.level = Logger::DEBUG

# Get all the repos inside of a project
def get_repos project_id
    $logger.info "Getting repos"

    # from the bitbucket api
    rest_endpoint = "/rest/api/1.0/projects/#{PROJECT_ID}/repos"

    http = Net::HTTP.new(BASE_GIT_URL, BASE_GIT_PORT)
    repos_request = Net::HTTP::Get.new("/rest/api/1.0/projects/#{PROJECT_ID}/repos?limit=1000")
    repos_request.basic_auth GIT_USER, GIT_PASSWORD
    repos_response = http.request(repos_request)
    repos_response.value

    # https://confluence.atlassian.com/bitbucket/what-is-a-slug-224395839.html
    repos_body = JSON.parse(repos_response.body)
    repos = repos_body['values'].map { |v| v['slug'] }

    $logger.info "Found repos #{repos}"

    return repos
end

# Clone the repos if they don't already exist
def clone_repos repos
    $logger.info "Detecting if clones repos #{repos}"
    failed_repos = []
    repos.each do |repo|
        repo_path = "#{GIT_DIR}/#{repo}"
        # TODO: Use ssh instead of http
        clone_url = "http://#{GIT_USER}:#{GIT_PASSWORD}@#{BASE_GIT_URL}:#{BASE_GIT_PORT}/scm/#{PROJECT_ID}/#{repo}.git"
        unless `git --git-dir='#{repo_path}/.git' --work-tree='#{repo_path}' config --get remote.origin.url`.to_s.strip == clone_url
            $logger.info "No git repo found or invalid git repo detected at #{repo_path}. Deleting and recloning project #{repo}"
            # If for some reason we didn't detect that it's a git repo, just clear the whole directory
            # And reclone (note that we only need to clone the latest commit on the master branch)
            successfully_cloned = system "git clone #{clone_url} --branch master --single-branch --depth 1 #{repo_path}"
            unless successfully_cloned
                $logger.warn "Could not git clone repo #{clone_url} to #{repo_path}"
                failed_repos.push repo
                FileUtils.rm_rf repo_path
            end
        end
        # Make sure the git repos are unmodified before we do anything
        `git --git-dir='#{repo_path}/.git' --work-tree='#{repo_path}' reset --hard HEAD`
    end
    $logger.info "Removing failed repos #{failed_repos}"
    repos -= failed_repos
    return repos
end

# Take the first file with the string readme and use that as the readme
# TODO: Find a better way to detect the readme
def find_readme repo_dir
    files = Dir.entries(repo_dir).sort
    files.each { |f| return f if f.downcase.include? 'readme' }
    return ''
end

# The meat and bones of this tool
# Recursively parses a markdown file looking for references to other files
# that also need to be parsed
# Returns bool, []
# Returns true if markdown file was successfully parsed, and an array of all relevant uris
def parse_markdown_file file_uri, parsed_uris=Set.new
    $logger.info "Parsing '#{file_uri}'"
    parsed_uris.add file_uri
    begin
        markdown_text = File.read(file_uri)
        markdown_tree = Kramdown::Document.new(markdown_text)
    rescue Exception => e
        # Continue on even if we can't parse a file
        # because the markdown file could have put in broken links
        # Or if a uri has a # tag in it
        $logger.warn("Could not read markdown file '#{file_uri}' => #{e}")
        return false, []
    end
    # A set of uris which are actually references to a real local file
    valid_uris = Set.new [file_uri]
    relative_uris = find_relative_uris markdown_tree
    $logger.debug("Detected relative uris in '#{file_uri}': '#{relative_uris}'")
    relative_uris.each do |uri|
        $logger.debug("File '#{uri}' in previously parsed files #{parsed_uris.inspect}: #{parsed_uris.include? uri}")
        unless parsed_uris.include? uri
            $logger.debug("Detected new file in '#{file_uri}' to parse: '#{uri}'")
            is_valid_markdown, new_valid_uris = parse_markdown_file uri, parsed_uris
            parsed_uris.add uri
            if is_valid_markdown
                $logger.debug("Adding file '#{uri}' because  it is valid markdown: #{is_valid_markdown}")
                valid_uris.merge new_valid_uris
            # Even if it's not markdown,
            # If we find a link to a local file (e.g. an image)
            # add it as a valid uri
            elsif File.file?(uri)
                $logger.debug("Adding file '#{uri}' because it is found locally.")
                valid_uris.add uri
            end
        end
    end
    $logger.debug "Valid uris connected to '#{file_uri}': '#{valid_uris.inspect}'"
    return true, valid_uris
end

# Searches through the tree and gets all uri and image elements
# and checks if the element is an absolute or relative url.
# We assume that if the uri is absolute, then it is not a local file that we need to parse
def find_relative_uris markdown_tree
    uris = _find_links_in_markdown_tree markdown_tree.root
    uris.delete_if do |uri|
        # http://stackoverflow.com/questions/1805761/check-if-url-is-valid-ruby
        # delete if we detect that it's an actual absolute uri
        abs_url = (uri =~ /\A#{URI::regexp}+\z/) != nil
        $logger.debug("Deleting absolute uri: '#{uri}'") if abs_url
        abs_url
    end
    # TODO: How do I want to deal with something that has tags?
    # For instance if the only link to another file is 'goober/goo.md#some_tag'
    # To deal with a link that potentially has a tag in it
    # We'll just try both options. The one without the tag and the one with the tag
    return uris
end

def is_uri_relative uri
    $logger.debug "URI '#{uri}' is relative? #{(uri =~ /\A#{URI::regexp}+\z/) == nil}"
    return (uri =~ /\A#{URI::regexp}+\z/) == nil
end

# Private method specific to kramdown to recursively search through the tree
# and grab all urls and images
def _find_links_in_markdown_tree markdown_tree_node
    case markdown_tree_node.type
    when :a
        links = [markdown_tree_node.attr['href']]
    when :img
        links = [markdown_tree_node.attr['src']]
    else
        links = []
    end
    markdown_tree_node.children.each { |child| links.concat _find_links_in_markdown_tree child }
    return links
end


# I"M BAD

# CALL THIS FROM INSIDE MAIN FOR REPOS LOOP
def find_replace_through_md_files files, repo
    files.each do |file|
        # puts "TRYING TO READ '#{file}' from '#{FileUtils.pwd}'"
        begin
            markdown_text = File.read(file)
            markdown_tree = Kramdown::Document.new(markdown_text)
            _add_repo_to_rel_links_in_markdown_tree markdown_tree.root, repo
            File.write(file, markdown_tree.to_kramdown)
        rescue Exception => e
            $logger.info "Exception happened in '#{file}' in #{FileUtils.pwd} => #{e}"
        end
    end
end

# Private method specific to kramdown to recursively search through the tree
# and grab all urls and images
def _add_repo_to_rel_links_in_markdown_tree markdown_tree_node, repo
    $logger.info "ITERATING THROUGH NODE #{markdown_tree_node.inspect}"
    found_link = false
    case markdown_tree_node.type
    when :a
        attr_name = 'href'
        found_link = true
    when :img
        attr_name = 'src'
        found_link = true
    end
    if found_link
        $logger.info "Found link to check '#{markdown_tree_node.attr[attr_name]}' in #{markdown_tree_node.inspect}"
        if is_uri_relative(markdown_tree_node.attr[attr_name])
            $logger.info "Attempting to prepend repo '#{repo}' to link '#{markdown_tree_node.attr[attr_name]}'"
            markdown_tree_node.attr[attr_name].prepend "#{repo}/"
        end
    end
    markdown_tree_node.children.each { |child| _add_repo_to_rel_links_in_markdown_tree child, repo }
end

# END ME BEING BAD

def main
    # Don't do anything if we haven't defined project id
    return 0 if PROJECT_ID == nil
    repos = get_repos PROJECT_ID
    successful_repos = clone_repos repos
    all_file_paths = Set.new

    # Used so we know which files map per repo
    files_per_repo = {}
    successful_repos.each do |repo|
        repo_path = "#{GIT_DIR}/#{repo}"
        FileUtils.chdir repo_path do
            $logger.info "Processing '#{repo_path}'"
            readme_path = find_readme repo_path
            all_file_paths.add "#{repo}/#{readme_path}"
            is_valid_markdown, linked_markdown_file_paths = parse_markdown_file readme_path
            all_file_paths.merge linked_markdown_file_paths.map { |path| "#{repo}/#{path}" }

            files_per_repo[repo] = Set.new [readme_path]
            files_per_repo[repo].merge linked_markdown_file_paths
        end
    end

    $logger.info "Performing find and replace"
    successful_repos.each do |repo|
        repo_path = "#{GIT_DIR}/#{repo}"
        FileUtils.chdir repo_path do
            find_replace_through_md_files files_per_repo[repo], repo
        end
    end
    print all_file_paths.to_a.join ' '
end

main()
