#include <stdio.h>

//line comment

/*
 * block comment
 *
 */

/*This is a block comment as well*/

//setThis();  //commented out code /* a comment in a line comment "XXX" */

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
