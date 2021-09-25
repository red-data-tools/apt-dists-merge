#!/usr/bin/env ruby

$VERBOSE = true

test_dir = __dir__

require "test-unit"

require_relative "helper"

exit(Test::Unit::AutoRunner.run(true, test_dir))
