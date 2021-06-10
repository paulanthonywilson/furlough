---
layout: post
title: Lessons from reading ostruct.rb
---

During this month's [Scottish Ruby User Group](http://www.scotrug.org) meeting we paired up read some code. We choose the [source for OpenStruct](https://github.com/ruby/ruby/blob/trunk/lib/ostruct.rb) as it was small and self-contained enough to get through in the hour or so available.

I expected it to be dull, but it was great fun and we all learnt a lot, mostly about stuff I should have known about Ruby, but had missed or forgotten. Here's some highlights:-

## OpenStruct implementation

First let's quickly revise what on what an OpenStruct does. From the documentation:

>  An OpenStruct is a data structure, similar to a Hash, that allows the definition of arbitrary attributes with their accompanying values. This is accomplished by using Ruby's metaprogramming to define methods on the class itself.

So you can do the following:-

{% highlight ruby  %}

require 'ostruct'

o = OpenStruct.new
o.name = "Mavis" # arbitrarily create an attribute (name) and assign a value
puts o.name

{% endhighlight %}

While OpenStruct is similar to Hash, it isn't a Hash; it does not extend Hash (or include Enumerable). The attributes are stored in a Hash member variable (@table) (see  [the initialize method](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L87-88)). New attributes are captured using [method_messing](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L176-191) and the accessors are [defined as methods](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L166-173) on the object.

## Freezing an OpenStruct

Freezing a Ruby object is supposed to prevent modifications. By default, this is achieved by disallowing assignment to instance variables. As the OpenStructs attributes are stored within a Hash that is assigned on initialisation(@table), then this alone would not prevent assigning values to an OpenStruct; while the OpenStruct would be frozen, @table would not be.

OpenStruct prevents assigning to frozen objects by all write operations accessing @table through the method [modifiable](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L151-159).

{% highlight ruby %}
#
  def modifiable
    begin
      @modifiable = true
    rescue
      raise RuntimeError, "can't modify frozen #{self.class}", caller(3)
    end
    @table
  end

  protected :modifiable

{% endhighlight %}

Assigning a value to @modifiable will raise an error, if the object has been frozen.

Another way of ensuring an OpenStruct is properly frozen might be to override the freeze method.

{% highlight ruby %}

  #NOT COPIED FROM ostruct.rb
  def freeze
    @table.freeze
    super
  end  

{% endhighlight %}

My guess is that this method was not followed as it would have made it harder to control the error message and stack; the error would be "can't modify frozen Hash", not "can't modify frozen OpenStruct".

## Massaging the backtrace

When errors are raised (in [modifiable](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L155) and [method](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L181)_[missing](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L187-189)) the backtrace is modified to start at the offending piece of client code. I like this - that's where the debugging programmer needs to look to work out a fix, not in the middle of the library code which has had its contract violated.

## define_singleton_method

[define_singleton_method](http://ruby-doc.org/core-1.9.3/Object.html#method-i-define_singleton_method) is method on Object that was introduced in Ruby 1.9, but had passed all us ScotRUG members by. It does what it says - defines a method on an object's singleton class: that is it defines a method on an object instance without affecting other instances of its class. Prior to 1.9, the method would need to be retrieved - messy business.

This is the [current](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L169-170) way OpenStruct dynamically defines methods:-

{% highlight ruby %}
#
  define_singleton_method(name) { @table[name] }
  define_singleton_method("#{name}=") { |x| modifiable[name] = x }
{% endhighlight %}

The [1.8.7](https://github.com/ruby/ruby/blob/v1_8_7_17/lib/ostruct.rb#L73-75) way is a little less readable:-


{% highlight ruby %}
#
  meta = class << self; self; end
  meta.send(:define_method, name) { @table[name] }
  meta.send(:define_method, :"#{name}=") { |x| @table[name] = x }

{% endhighlight %}

## singleton_class

There's no opposite of _define_singleton_method;  _remove_singleton_method isn't a thing. So, [delete_field](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L223-226) finds itself dealing directly with the object's singleton class.


{% highlight ruby %}
#
  def delete_field(name)
    sym = name.to_sym
    singleton_class.__send__(:remove_method, sym, "#{sym}=")
    @table.delete sym
  end
{% endhighlight %}

[singleton_class](http://www.ruby-doc.org/core-1.9.2/Object.html#method-i-singleton_class) was introduced in 1.9.2 to be used in place of

{% highlight ruby %}

(class << self; self; end)

{% endhighlight %}

[This](https://www.ruby-forum.com/topic/177294) is the feature request thread for _singleton_class_.


## id2name

In method_missing [we found](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L177):-

{% highlight ruby %}

  #
  def method_missing(mid, *args) # :nodoc:
    mname = mid.id2name
{% endhighlight %}

I have never seen _id2name_ before. It is a method on Symbol that [returns the string corresponding to the symbol](http://ruby-doc.com/docs/ProgrammingRuby/html/ref_c_symbol.html#Symbol.id2name). I've always used _to_s_ for that, which apparently is a [synonym for _id2name](http://ruby-doc.com/docs/ProgrammingRuby/html/ref_c_symbol.html#Symbol.to_s).

¯\\_(ツ)_/¯


## to_enum

Being a bit like a Hash, OpenStruct provides the [each_pair](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L127-130) method for iterating over the key-value pairs:-


{% highlight ruby %}

  #
  def each_pair
    return to_enum(__method__) { @table.size } unless block_given?
    @table.each_pair{|p| yield p}
  end
{% endhighlight %}

Delegating to the @table Hash is straightforward enough. Using _to_enum_ to return an enumerator needed a bit more reading.

_to_enum is defined on object and [creates a new enumerator, by calling the passed-in method](http://ruby-doc.org/core-2.1.2/Object.html#method-i-to_enum). So by getting an enumerator from _each_pair_, here's what happens:-

1. Call each_pair without a block
1. to_enum on the instance is called passing in _each_pair_ as the method_name.
1. This time a block will be passed in, allowing the iteration (delegated to @table)

The number of attributes stored (@table.size) is given to to_enum as the return value of a block, because that's how it is optionally done.

Using the return value of a block to get an optional value is a bit unusual. _to_enum_ uses this, as it already has optional values in its method signature - arguments to pass to the method that takes the block.


## initialize_copy

This is a private method on Object which is called when *dup* or *clone* are used to create a copy (or clone). See [Jon Leighton's blog post](http://www.jonathanleighton.com/articles/2011/initialize_clone-initialize_dup-and-initialize_copy-in-ruby/).

{% highlight ruby %}
#
  def initialize_copy(orig)
    super
    @table = @table.dup
    @table.each_key{|key| new_ostruct_member(key)}
  end


{% endhighlight %}

OpenStruct overrides this [initialize_copy](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L99-103) to ensure that a copied object, gets a duplicate version of the @table Hash holding the key value pairs; otherwise the copy would share that data store, which would get weird. It also ensures that the dynamic methods are defined on the new copy; copy (unlike clone) does not duplicate the singleton class, so they would otherwise be missing.



## protected members

I don't see the _protected_ keyword used much in application ruby code. I think being able to override encapsulation with _send_ has made us a bit lazy. Allowing the @table data store to be read through a protected accessor, means it can be accessed by other OpenStruct instances when checking equality.


{% highlight ruby %}
#
  attr_reader :table # :nodoc:
  protected :table

  def ==(other)
    return false unless other.kind_of?(OpenStruct)
    @table == other.table
  end
{% endhighlight %}



## inspect

Inspect shows the contents of the OpenStruct in "key=value" form, where inspect is called on each of the values. Straightforward?  You would think so, but here's [the implementation](https://github.com/ruby/ruby/blob/v2_1_2/lib/ostruct.rb#L234-254):


{% highlight ruby %}
#
  InspectKey = :__inspect_key__ # :nodoc:
  def inspect
    str = "#<#{self.class}"

    ids = (Thread.current[InspectKey] ||= [])
    if ids.include?(object_id)
      return str << ' ...>'
    end

    ids << object_id
    begin
      first = true
      for k,v in @table
        str << "," unless first
        first = false
        str << " #{k}=#{v.inspect}"
      end
      return str << '>'
    ensure
      ids.pop
    end
  end

{% endhighlight %}

The thread current storage is a bit confusing at first. It's purpose is to guard against infinite recursion, if an OpenStruct instance is stored in itself.

{% highlight ruby %}

>> o = OpenStruct.new
=> #<OpenStruct>
>> o.o=o
=> #<OpenStruct o=#<OpenStruct ...>>
>> 

{% endhighlight %}

The object ids of all the OpenStructs currently being inspected are stored in the Thread.current, to ensure that they are only inspected once.

{% highlight ruby %}
#
  if ids.include?(object_id)
      return str << ' ...>'
  end

{% endhighlight %}

Evan Phoenix suggested that we should read code, in [his keynote](http://programme2014.scottishrubyconference.com/slots/3/video) at this year's Scottish Ruby Conference. Picking apart some well-written code is a great way to pick up on all the things you should know, but have somehow missed or forgotten.
