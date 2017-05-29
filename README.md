# What is this?

This project is a list of tools to generate list of markdown files in a git project (which contains a list of repos).

This project consists of three tools.

*markdown_extractor.rb*: This grabs a list of repos from a project and generates a list of files that are referenced by the readme.

* Note: This can be optimized by [browsing](https://developer.atlassian.com/static/rest/bitbucket-server/5.0.1/bitbucket-rest.html#idm45993793705776) the files instead of cloning the full repos.
* Note: This can also be optimized this by adding concurrency so that each repo we find in the project searches the readmes concurrently.

*book_generator.rb*: This takes in a list of files and creates the `SUMMARY.md` and base `README.md` files.

*link_modifier.rb*: This prepends the `repo` the markdown file belongs to, to all of the relative uris in all of the markdown files in the output folder. This is necessary because the tool we want to use (`udocs`) requires the uris to have the full path (instead of the relative path).

* Note: This can be optimized by going through the list of files concurrently.

There is also a `run.sh` file that shows you how to use the tools together.