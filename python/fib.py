"""
  Testing Python block comment.
  Use "C-t" for 2 space TABS
  and "C-o" to erase 2 spaces.
""" 

def fib(n):
  if n<2:
    return 1
  else:
    return (fib(n-1)+fib(n-2))

# Definitions of "C-t" and "C-o"
# are given in  ~/init.lsp
# You will need 
# sudo femto ~/init.lsp
# in order to change ~/init.lsp
