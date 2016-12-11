=begin
 An example of ruby program.
 The file name "fib.rb" must
 have the ".rb" extension.
=end

def fib(n)
  return 1 if (0..1).include? n
  ( fib(n - 1) + fib(n - 2))
end

$xs= "Here's she!"
$xt= 'Use the ".rb" extension.'

puts fib(5)

# End of program.