require 'set'
require 'date'
require 'benchmark/ips'

ALLOWED_IN_KEYS = [
  ::String,
  ::Symbol,
  ::Numeric,
  ::TrueClass,
  ::FalseClass,
  ::NilClass,
  ::Integer,
  ::Float,
  ::Date,
  ::DateTime,
  ::Time,
].to_set
parts = RUBY_VERSION.split('.').map(&:to_i)
unless parts[0] >= 2 and parts[1] >= 4
  ALLOWED_IN_KEYS << ::Fixnum
  ALLOWED_IN_KEYS << ::Bignum  
end

EXAMPLES = [
  'hi',
  :there,
  123,
  123.54,
  1e99,
  123456789 ** 2,
  1e999,
  true,
  false,
  nil,
  Date.new(2015,1,1),
  Time.now,
  DateTime.now,
  Mutex,
  Mutex.new,
  Benchmark,
  { hi: :world },
  [[]],
  Fixnum,
  Struct,
  Struct.new(:a),
  Struct.new(:a).new(123)
]
EXAMPLES.each do |example|
  puts "#{example} -> #{example.class}"
end

puts

[
  Date.new(2015,1,1),
  Time.now,
  DateTime.now,
].each do |x|
    puts x.to_s
end

puts

EXAMPLES.each do |example|
  a = ALLOWED_IN_KEYS.any? { |thing| example.is_a?(thing) }
  b = ALLOWED_IN_KEYS.include? example.class
  unless a == b
    raise "#{example.inspect}: #{a.inspect} vs #{b.inspect}"
  end
end

Benchmark.ips do |x|
  x.report("any") do
    example = EXAMPLES.sample
    y = ALLOWED_IN_KEYS.any? { |thing| example.is_a?(thing) }
    a = 1
    y
  end

  x.report("include") do
    example = EXAMPLES.sample
    y = ALLOWED_IN_KEYS.include? example.class
    a = 1
    y
  end

end
