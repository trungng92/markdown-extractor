#!/bin/bash
./markdown_extractor.rb | xargs ./book_generator.rb && ./link_modifier.rb
