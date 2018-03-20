---
title: Search Ruby Method Declarations in vim
layout: post
published: true
---

While searching method declarations in vim can be tricky and you can use `ctags`, I found that using `ag` or [the silver searcher](https://github.com/ggreer/the_silver_searcher) yields great results.

I've been an active vim user for almost 2 years now and primarily develop Rails apps. I started using vim because I really liked the idea of having your entire development environment on one screen.

Run your server, tests, install gems, write code, without leaving or `Alt + Tab`'ing out.

As developers, we occasionally find the need to search for the method declaration. Here are a couple `vimscript` functions you can use along with `<Leader>` commands to efficiently search for the method declarations and increase productivity.

{% highlight vim %}
function! SearchForDeclarationCursor()
  let searchTerm = expand("<cword>")
  call SearchForDeclaration(searchTerm)
endfunction
{% endhighlight %}

Here we just expand and capture the word where the cursor is.

{% highlight vim %}
function! SearchForDeclaration(term)
  let definition = 'def ' . a:term
  cexpr system('ag -w ' . shellescape(definition))
endfunction
{% endhighlight %}

This function prepends the word `def` with the search term. This will give you a string like `def some_method`. `system` function executes any `bash` commands provided to it. The `-w` option matches the exact search term, thereby giving us accurate results.

And finally, we can map this to a `<Leader>` command.

{% highlight vim %}
map <Leader>cd :call SearchForDeclarationCursor()<CR>
{% endhighlight %}

Hope this helps ya'll!