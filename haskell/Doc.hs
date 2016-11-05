module Doc where

import Data.List (isInfixOf)

data Document = Buffer (Int, Int, Int) Int [[Char]] [Char] [[Char]]
    deriving (Show)

fillDocument :: String -> Document
fillDocument input = Buffer (1, 6, 15) 1 [] (head readin) (tail readin)
    where readin = lines input

appendLine :: Document -> [Char] -> Document
appendLine (Buffer ice 0 [] [] []) newline = Buffer ice 1 [] newline [] 
appendLine (Buffer ice lineNum prev cur post) newline = 
                Buffer ice (lineNum + 1) (cur : prev) newline post

searchString m str (Buffer ice n prev cur post)
    | isInfixOf str cur = n
searchString m str (Buffer ice n prev cur (x:post))=
    searchString m str (Buffer ice (n+1) (cur:prev) x post)
searchString m str (Buffer ice n prev cur [])= m  

insertLine :: Document -> [Char] -> Document
insertLine (Buffer ice 0 [] [] []) newline = Buffer ice 1 [] newline [] 
insertLine (Buffer ice lineNum prev cur post) newline = 
                Buffer ice lineNum prev newline (cur : post)

deleteLine :: Document -> Document
deleteLine (Buffer ice 0 _  _ _ )   = Buffer ice 0 [] [] []
deleteLine (Buffer ice _ [] _ post) = Buffer ice 1 [] (head post) (tail post)
deleteLine (Buffer ice lineNum prev _ post) = 
                   Buffer ice (lineNum - 1) (tail prev)  (head prev) post

replaceLine :: Document -> String -> Document
replaceLine (Buffer ice lineNum prev cur post) newline =
                                Buffer ice lineNum prev newline post

gotoLine :: Document -> Int -> Document
gotoLine org@(Buffer ice lineNum prev cur post) newline
    | newline < 1       = gotoLine org 1
    | lineNum > newline = gotoLine (Buffer ice (lineNum-1) 
                                           (tail prev) 
                                           (head prev) 
                                           (cur:post)) newline  
    | post == []         = org
    | lineNum < newline = gotoLine (Buffer ice (lineNum+1) 
                                           (cur:prev) 
                                           (head post) 
                                           (tail post)) newline  
    | otherwise         = org

numString :: Document -> String
numString (Buffer ice n _ cur post)= unlines 
                                  (zipWith (++)  
                                    [(show i) ++ "- " | i <- [n..1000]]
                                    (cur:post))

from1NumString :: Document -> String
from1NumString (Buffer ice 1 _ cur post)= unlines 
                                  (zipWith (++)  
                                    [(show i) ++ "- " | i <- [1..1000]]
                                    (cur:post))
from1NumString doc= from1NumString $ gotoLine doc 1

mkNumCursor csr n | n < 10  = (show n)++"   "++csr
mkNumCursor csr n | n < 100 = (show n)++"  "++csr
mkNumCursor csr n | n < 1000= (show n)++" "++csr
mkNumCursor csr n = (show n)++csr

indent n= [' ' | x <- [1..n]]

getBefore i n [] cur post = (n, cur:post)
getBefore 0 n (x1:xs) cur post= (n,  cur:post)
getBefore i n (x1:xs) cur post= getBefore (i-1) (n-1) xs x1 (cur:post)

nonumBefore i n [] cur post = (n, cur:post)
nonumBefore 0 n (x1:xs) cur post= (n,  cur:post)
nonumBefore i n (x1:xs) cur post= nonumBefore (i-1) (n-1) xs x1 (cur:post)

allToString :: Document -> String
allToString (Buffer ice 1 _ cur post) = unlines (cur:post) 
allToString doc = allToString $ gotoLine doc 1

gLin (Buffer ice n _ x _)= (x, "")

cursorLine (Buffer ice n _ _ aftr) =  (mkNumCursor "$ " n)

appendCursor (Buffer ice n _ _  aftr)=  (mkNumCursor "@ " n)

insCursor (Buffer ice n _ _  aftr)=  (mkNumCursor "i " n)

searchit str (Buffer ice m prev cur aftr) =
   searchString m str (Buffer ice m prev cur aftr)

tl (x:xs)= xs

executeCommand :: [Char] -> Document -> Document
executeCommand [] doc = doc 
executeCommand command doc 
    | abriv == 'd'              = deleteLine doc
    | abriv == 'g' && args == 1 = gotoLine doc (((read.head.(drop 1).words) 
                                                      command)::Int )
    | abriv == '/'  = gotoLine doc (searchit (tl command)  doc)
    | abriv == 'r' && args >= 1 = replaceLine doc stament
    | abriv == 'i' && args >= 1 = insertLine doc stament
    | abriv == 'a' && args >= 1 = appendLine doc stament
    | abriv == 'b' = appendLine doc []
    | otherwise    = doc
        where abriv   = (head.head.words) command
              stament = ((tail.dropWhile (/=' ')).tail) command
              args    = length.tail.words $ command

linJ (Buffer ice n _ _ _)= ("g " ++ (show (n+1)))
linK (Buffer ice n _ _ _)= ("g " ++ (show (n-1)))

mkInsertion Nothing doc= doc
mkInsertion (Just stament) doc=  insertLine doc stament

prefixp ('>':'i':'m':'p':'o':'r':'t':x)= True
prefixp ('>':'-':'-':x)= True 
prefixp ('>':'m':'o':'d':'u':'l':'e':' ':x)= True
prefixp ('i':'m':'p':'o':'r':'t':x)= True
prefixp ('m':'o':'d':'u':'l':'e':' ':x)= True
prefixp ('-':'-':x)= True 

prfx ('>':'i':'m':'p':'o':'r':'t':x)= ("import", x)
prfx ('>':'-':'-':x)= ('>':'-':'-':x, []) 
prfx ('>':'m':'o':'d':'u':'l':'e':' ':x)= (">module ", x)
prfx ('i':'m':'p':'o':'r':'t':x)= ("import", x)
prfx ('m':'o':'d':'u':'l':'e':' ':x)= ("module", x)
prfx ('-':'-':x)= ('-':'-':x, []) 

