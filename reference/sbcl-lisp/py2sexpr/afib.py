def fib(n):
    if (n < 2):
        return 1
    else:
        return fib(n-1)+fib(n-2)

print(fib(40))  # Python takes forever on this one

