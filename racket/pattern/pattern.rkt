#lang racket/base

(provide match match* with when ->
         _
         ~var
         ~pred
         ~=
         ~and
         ~or
         ~refine
         cons
         list*
         list
         quote
         (for-syntax base-pattern-transformer
                     normal+base-pattern
                     make-var-like-transformer
                     syntax-class
                     full-pattern
                     pattern-data-constructor))

(require racket/match
         (prefix-in rkt-
           (combine-in racket/base
                       racket/match))
         syntax/parse/define
         "matcher.rkt"
         (for-syntax racket/base
                     syntax/parse
                     syntax/parse/experimental/reflect
                     syntax/parse/define
                     syntax/transformer
                     syntax/apply-transformer
                     struct-like-struct-type-property))

(begin-for-syntax
  (define (make-var-like-transformer id)
    (set!-transformer-procedure (make-variable-like-transformer id)))
  (define-simple-macro (syntax-class stuff ...)
    (let ()
      (define-syntax-class reified-class stuff ...)
      (reify-syntax-class reified-class))))

;; -------------------------------------------------------------------

;; Syntax

;;     pattern = _
;;             | {~var id}         ; shorthand: id
;;             | (quote datum)     ; shorthand: boolean, number, string, char
;;             | {~= expression}
;;             | {~pred expression}
;;             | {~or pattern ...}
;;             | {~and pattern ...}
;;             | {~refine pattern expression}
;;             | (constructor pattern ...)

;; -------------------------------------------------------------------

;; Internal representation

;; A Pattern has compile-time attributes:
;;  * matcher : ExprSyntax for an expression of type [Matcher X Y (Z ...)]
;;  * out ... : [Listof Id] for the Zs
;; A BasePatternId is an identifier bound with `define-syntax` or
;; `let-syntax` to a BasePatternTransformer.
;; A BasePatternTransformer is a (base-pattern-transformer SyntaxClass)
;; where the syntax class binds the attributes `matcher` and `out`
;; above.
(begin-for-syntax
  (define-struct-like-struct-type-property base-pattern-transformer
    [class]))

(begin-for-syntax
  (struct normal+base-pattern [normal base-pattern]
    #:property prop:procedure (struct-field-index normal)
    #:property prop:base-pattern-transformer
    (λ (self)
      (base-pattern-transformer
       (normal+base-pattern-base-pattern self))))
  (define-syntax-class base-pattern
    #:attributes [[matcher 0] [out 1]]
    [pattern {~and stx {~or m (m . _)}}
      #:declare m (static base-pattern-transformer? "pattern")
      #:with {~and props [matcher* [out ...]]}
      (local-apply-transformer
       (syntax-parser
         #:track-literals
         [{~reflect x
            ((base-pattern-transformer-class (attribute m.value)))
            #:attributes [[matcher 0] [out 1]]}
          #'[x.matcher [x.out ...]]])
       #'stx
       'expression)
      #:with matcher (syntax-track-origin
                      (syntax-track-origin
                       (syntax-parse-track-literals #'matcher*)
                       #'stx #'m)
                      #'props #'m)])
  (define-syntax-class full-pattern
    #:attributes [[matcher 0] [out 1]]
    [pattern :base-pattern]
    [pattern x:id #:with :base-pattern #'{~var x}]
    [pattern {~and x {~or :boolean :number :str :bytes :char}}
      #:with :base-pattern #'(quote x)])

  (define-syntax-class (pattern-data-constructor ctor-matcher)
    [pattern (_ p:full-pattern ...)
      #:with matcher #`(#,ctor-matcher p.matcher ...)
      #:with [out ...] #'[p.out ... ...]])
  )

(define-syntax _
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern :id #:with matcher #'any/p #:with [out ...] '()])))

(define-syntax ~var
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ x:id) #:with matcher #'var/p #:with [out ...] #'[x]])))

(define-syntax ~=
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ e:expr)
      #:with matcher #'(equal/p e)
      #:with [out ...] '()])))

(define-syntax ~pred
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ e:expr)
      #:with matcher #'(pred/p e)
      #:with [out ...] '()])))

(define-syntax ~and
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ pat:full-pattern ...)
      #:with matcher #'(and/p pat.matcher ...)
      #:with [out ...] #'[pat.out ... ...]])))

(define-syntax ~refine
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ pat:full-pattern prop:expr)
      #:with matcher #'(refine/p pat.matcher
                                 (match-lambda [(list pat.out ...) prop]))
      #:with [out ...] #'[pat.out ...]])))

(define-syntax ~or
  (base-pattern-transformer
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ pat:full-pattern ...)
      #:do [(define init
              (if (null? (attribute pat.out)) '() (car (attribute pat.out))))]
      #:with [out ...]
      (for/fold ([acc init])
                ([one (in-list (attribute pat.out))])
        (filter (λ (x) (member x one bound-identifier=?)) acc))
      #:with matcher
      #'(match-lambda
          [(app pat.matcher (list pat.out ...)) (list out ...)]
          ...
          [_ #false])])))

(define-syntax cons
  (normal+base-pattern
   (make-var-like-transformer #'rkt-cons)
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern {~var || (pattern-data-constructor #'cons/p)}])))

(define-syntax list*
  (normal+base-pattern
   (make-var-like-transformer #'rkt-list*)
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern {~var || (pattern-data-constructor #'list*/p)}])))

(define-syntax list
  (normal+base-pattern
   (make-var-like-transformer #'rkt-list)
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern {~var || (pattern-data-constructor #'list/p)}])))

(define-syntax quote
  (normal+base-pattern
   (syntax-parser
     [(_ datum) #'(rkt-quote datum)])
   (syntax-class
    #:attributes [matcher [out 1]]
    [pattern (_ datum)
      #:with matcher #'(equal/p (rkt-quote datum))
      #:with [out ...] '()])))

(define-syntax with #f)
(define-syntax when #f)
(define-syntax -> #f)

(begin-for-syntax
  (define-splicing-syntax-class full-pattern/when
    #:attributes [matcher [out 1]]
    #:literals [when]
    [pattern {~seq pa:expr {~peek-not when} ~!}
      #:with :full-pattern #'pa]
    [pattern {~seq pa:expr when ~! pr:expr}
      #:with :full-pattern #'{~refine pa pr}]))

(define-syntax-parser match
  #:track-literals
  #:literals [with ->]
  [(_ e with [pattern:full-pattern/when -> body:expr] ...)
   #'(rkt-match e
       [(app pattern.matcher (list pattern.out ...)) body]
       ...)])

(define-syntax-parser match*
  #:track-literals
  #:literals [with ->]
  [(_ [e ...] with [[pattern:full-pattern ...] -> body:expr] ...)
   #'(rkt-match* [e ...]
       [[(app pattern.matcher (list pattern.out ...)) ...] body]
       ...)])
