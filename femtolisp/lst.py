import sys
w= sys.stdout.write

cons   = lambda el, lst: (el, lst)
car = lambda lst: lst[0] if lst else lst
cdr = lambda lst: lst[1] if lst else lst

def display(lst):
  if lst== None:
    print("nil\n")
  else:
    w("%s " % car(lst))
    display(cdr(lst))

def app(xs, ys):
  if lst== None:
    return ys
  else:
    return cons(car(xs), app(cdr(xs), ys))

def toList(v, i):
  if i >= len(v):
     return None
  else:
     return cons(v[i], toList(v, i+1))

