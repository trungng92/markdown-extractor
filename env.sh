#!/bin/bash

# Location to clone the repos to (if they don't exist)
export GIT_DIR='/tmp/markdown_extractor/git'

# Base directory where all the files will be copied to
# Note that file structure will be preserved when copied
# Note that OUTPUT_DIR must be empty or this will throw an exception
export OUTPUT_DIR='/tmp/markdown_extractor/output'

# Project under which repos are located
# For github, this will be the user
export PROJECT_ID=''

# Base url to access git projects/repos
export BASE_GIT_URL=''
export BASE_GIT_PORT=''

# Robot user to access git repos
export GIT_USER=''
export GIT_PASSWORD=''
