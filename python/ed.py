""" 
 The program below calls  femtoemacs
 from Python "REPL". After editing the
 file, you can import and test the
 corresponding module normally. 
"""
import os

def edit(fName):
  command= "/usr/local/bin/femto " + fName
  status= os.system(command)
  return status

# Usage:
# >>> import ed
# >>> ed.editor("fib.py")
# >>> import fib
# where "fib.py" is the file name. 

 