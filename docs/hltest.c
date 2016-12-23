/*
 * block comment
 * "double quoted string'
 * 'single quoted string'
 * 1234567890
 * adbcedf ABCXYZ
 * !"£$%^&*()_=+{}[]:;@'~#<>,.?/
 *    //  line comment inside a block comment
 * \'  \"  \* *\/
 */

#include <stdio.h>

// /* block comment after a line comment */
// "double quoted string'
// 'single quoted string'
// 1234567890
// adbcedf ABCXYZ
// !"£$%^&*()_=+{}[]:;@'~#<>,.?/
//     //  line comment inside a block comment
//  \'  \"  \* *\/
// 

s1 = "/*";
s2 = "*/";
s3 = "\\";
s4 = "
A multiline string
second line of multiline string
// third line of multiline string - starts with line comment
/* fourth line starts with a block comment
  */
all lines should rendered in the string color
";



/* "string" */
/* 'string' */

/*
 * block comment
 *
 */

//example keyword
void func();
char s[] = "a string";
char c;

ptr->m_fish[3] = 0.0;

//1234567890

// all of these special cases should work or we should not attempt to highlght strings
c='"';   //a single quoted double quotes should work
c='\'';
s="'";  //a double quoted single quotes
s="\"";  //should work

int x = 1234567;

s="symbols inside a string !£$%^&**()_+={}[]:;@'~#<,>;//.?/\\|";
x="digits inside a string 0123456789 should show in the string color";

s="£";
s=":";

/* */
