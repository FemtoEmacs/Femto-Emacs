#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include "pdf-pages.h"
#ifdef __APPLE__
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#endif
int ttfy_render(const char *pdf, const char *range, const char *directory,
                char images[TTFY_MAX_PAGES][4096], int *first, int *last,
                char *error, size_t error_size)
{
#ifndef __APPLE__
    (void)pdf; (void)range; (void)directory; (void)images; (void)first; (void)last;
    snprintf(error,error_size,"Native PDF rendering currently requires macOS.");
    return 0;
#else
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)pdf,strlen(pdf),false);
    CGPDFDocumentRef doc=url ? CGPDFDocumentCreateWithURL(url) : NULL;
    if(url)CFRelease(url);
    if(!doc){snprintf(error,error_size,"Cannot open PDF (invalid, unreadable or encrypted).");return 0;}
    int count=(int)CGPDFDocumentGetNumberOfPages(doc), a=1,b=count;
    const char *p=range;
    while(isspace((unsigned char)*p))p++;
    if(*p){
        char *end; long start=strtol(p,&end,10);
        if(end==p || start<1 || start>count)goto invalid;
        a=b=(int)start;p=end;
        while(isspace((unsigned char)*p))p++;
        if(*p=='-'){
            p++;long finish=strtol(p,&end,10);
            if(end==p || finish<a || finish>count)goto invalid;
            b=(int)finish;p=end;
        }
        while(isspace((unsigned char)*p))p++;
        if(*p)goto invalid;
    }
    if(b-a+1>TTFY_MAX_PAGES){
        snprintf(error,error_size,"PDF has %d selected pages; choose a range of at most %d pages.",b-a+1,TTFY_MAX_PAGES);
        CGPDFDocumentRelease(doc);return 0;
    }
    *first=a;*last=b;
    for(int page=a;page<=b;page++){
        CGPDFPageRef ref=CGPDFDocumentGetPage(doc,page);
        CGRect box=CGPDFPageGetBoxRect(ref,kCGPDFCropBox);
        int rotation=CGPDFPageGetRotationAngle(ref);
        size_t width=(size_t)(box.size.width*2+0.5),height=(size_t)(box.size.height*2+0.5);
        if(rotation%180){size_t swap=width;width=height;height=swap;}
        if(!width || !height || width>10000 || height>10000 || width*height>40000000){
            snprintf(error,error_size,"Unsupported page dimensions at page %d.",page);goto failed;
        }
        CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx=CGBitmapContextCreate(NULL,width,height,8,0,colors,kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colors);
        if(!ctx){snprintf(error,error_size,"Cannot render page %d.",page);goto failed;}
        CGContextSetRGBFillColor(ctx,1,1,1,1);CGContextFillRect(ctx,CGRectMake(0,0,width,height));
        /* Quartz's page transform does not upscale small pages. Scale the
           bitmap CTM explicitly, then fit in PDF points to retain 144 dpi. */
        CGContextScaleCTM(ctx,2,2);
        CGContextConcatCTM(ctx,CGPDFPageGetDrawingTransform(ref,kCGPDFCropBox,CGRectMake(0,0,width/2.0,height/2.0),0,true));
        CGContextDrawPDFPage(ctx,ref);
        CGImageRef image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);
        snprintf(images[page-a],4096,"%s/page-%04d.png",directory,page);
        CFURLRef target=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)images[page-a],strlen(images[page-a]),false);
        CGImageDestinationRef dest=target ? CGImageDestinationCreateWithURL(target,CFSTR("public.png"),1,NULL) : NULL;
        if(target)CFRelease(target);
        int ok=0;
        if(dest && image){CGImageDestinationAddImage(dest,image,NULL);ok=CGImageDestinationFinalize(dest);}
        if(dest)CFRelease(dest);
        if(image)CGImageRelease(image);
        if(!ok){snprintf(error,error_size,"Cannot save rendered page %d.",page);goto failed;}
    }
    CGPDFDocumentRelease(doc);return b-a+1;
invalid:
    snprintf(error,error_size,"Invalid page range; use blank for all, N, or N-M (PDF has %d pages).",count);
failed:
    CGPDFDocumentRelease(doc);return 0;
#endif
}
