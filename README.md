# LockAndCache

[![Build Status](https://travis-ci.org/seamusabshere/lock_and_cache.svg?branch=master&v=2.2.0)](https://travis-ci.org/seamusabshere/lock_and_cache)
[![Code Climate](https://codeclimate.com/github/seamusabshere/lock_and_cache/badges/gpa.svg?v=2.2.0)](https://codeclimate.com/github/seamusabshere/lock_and_cache)
[![Dependency Status](https://gemnasium.com/seamusabshere/lock_and_cache.svg?v=2.2.0)](https://gemnasium.com/seamusabshere/lock_and_cache)
[![Gem Version](https://badge.fury.io/rb/lock_and_cache.svg?v=2.2.0)](http://badge.fury.io/rb/lock_and_cache)
[![Security](https://hakiri.io/github/seamusabshere/lock_and_cache/master.svg?v=2.2.0)](https://hakiri.io/github/seamusabshere/lock_and_cache/master)
[![Inline docs](http://inch-ci.org/github/seamusabshere/lock_and_cache.svg?branch=master&v=2.2.0)](http://inch-ci.org/github/seamusabshere/lock_and_cache)

Lock and cache using redis!

Most caching libraries don't do locking, meaning that >1 process can be calculating a cached value at the same time. Since you presumably cache things because they cost CPU, database reads, or money, doesn't it make sense to lock while caching?

## Quickstart

```ruby
LockAndCache.storage = Redis.new

LockAndCache.lock_and_cache(:stock_price, {company: 'MSFT', date: '2015-05-05'}, expires: 10, nil_expires: 1) do
  # get yer stock quote
  # if 50 processes call this at the same time, only 1 will call the stock quote service
  # the other 49 will wait on the lock, then get the cached value
  # the value will expire in 10 seconds
  # but if the value you get back is nil, that will expire after 1 second
end
```

## Sponsor

<p><a href="https://www.faraday.io"><img src="https://s3.amazonaws.com/faraday-assets/files/img/logo.svg" alt="Faraday logo"/></a></p>

We use [`lock_and_cache`](https://github.com/seamusabshere/lock_and_cache) for [B2C customer intelligence at Faraday](http://faraday.io).

## TOC

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


  - [Theory](#theory)
  - [Practice](#practice)
    - [Setup](#setup)
    - [Locking](#locking)
    - [Caching](#caching)
      - [Standalone mode](#standalone-mode)
      - [Context mode](#context-mode)
  - [Special features](#special-features)
    - [Locking of course!](#locking-of-course)
    - [Heartbeat](#heartbeat)
    - [Context mode](#context-mode-1)
    - [nil_expires](#nil_expires)
  - [Tunables](#tunables)
  - [Few dependencies](#few-dependencies)
  - [Wishlist](#wishlist)
  - [Contributing](#contributing)
- [Copyright](#copyright)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Theory

`lock_and_cache`...

1. <span style="color: red;">returns cached value</span> (if exists)
2. <span style="color: green;">acquires a lock</span>
3. <span style="color: red;">returns cached value</span> (just in case it was calculated while we were waiting for a lock)
4. <span style="color: red;">calculates and caches the value</span>
5. <span style="color: green;">releases the lock</span>
6. <span style="color: red;">returns the value</span>

As you can see, most caching libraries only take care of (1) and (4) (well, and (5) of course).

## Practice

### Setup

```ruby
LockAndCache.storage = Redis.new
```

It will use this redis for both locking and storing cached values.

### Locking

Based on [antirez's Redlock algorithm](http://redis.io/topics/distlock).

Above and beyond Redlock, a 32-second heartbeat is used that will clear the lock if a process is killed. This is implemented using lock extensions.

### Caching

This gem is a simplified, improved version of https://github.com/seamusabshere/cache_method. In that library, you could only cache a method call.

In this library, you have two options: providing the whole cache key every time (standalone) or letting the library pull information about its context.

```ruby
# standalone example
LockAndCache.lock_and_cache(:stock_price, {company: 'MSFT', date: '2015-05-05'}, expires: 10) do
  # ...
end

# context example
def stock_price(date)
  lock_and_cache(date, expires: 10) do
    # ...
  end
end
def lock_and_cache_key
  company
end
```

#### Standalone mode

```ruby
LockAndCache.lock_and_cache(:stock_price, company: 'MSFT', date: '2015-05-05') do
  # get yer stock quote
end
```

You probably want an expiry

```ruby
LockAndCache.lock_and_cache(:stock_price, {company: 'MSFT', date: '2015-05-05'}, expires: 10) do
  # get yer stock quote
end
```

Note how we separated options (`{expires: 10}`) from a hash that is part of the cache key (`{company: 'MSFT', date: '2015-05-05'}`).

One other crazy thing: `nil_expires` - for when you want to check more often if the external stock price service returned nil

```ruby
LockAndCache.lock_and_cache(:stock_price, {company: 'MSFT', date: '2015-05-05'}, expires: 10, nil_expires: 1) do
  # get yer stock quote
end
```

Clear it with

```ruby
LockAndCache.clear :stock_price, company: 'MSFT', date: '2015-05-05'
```

Check locks with

```ruby
LockAndCache.locked? :stock_price, company: 'MSFT', date: '2015-05-05'
```

#### Context mode

"Context mode" simply adds the class name, method name, and context key (the results of `#id` or `#lock_and_cache_key`) of the caller to the cache key.

```ruby
class Stock
  include LockAndCache

  def initialize(company)
    [...]
  end

  def stock_price(date)
    lock_and_cache(date, expires: 10) do
      # the cache key will be StockQuote (the class) + get (the method name) + id (the instance identifier) + date (the arg you specified)
    end
  end

  def lock_and_cache_key # <---------- if you don't define this, it will try to call #id
    company
  end
end
```

The cache key will be StockQuote (the class) + get (the method name) + id (the instance identifier) + date (the arg you specified).

In other words, it auto-detects the class, method, context key ... and you add other args if you want.

Clear it with

```ruby
blog.lock_and_cache_clear(:get, date)
```

## Special features

### Locking of course!

Most caching libraries don't do locking, meaning that >1 process can be calculating a cached value at the same time. Since you presumably cache things because they cost CPU, database reads, or money, doesn't it make sense to lock while caching?

### Heartbeat

If the process holding the lock dies, we automatically remove the lock so somebody else can do it (using heartbeats and redlock extends).

### Context mode

This pulls information about the context of a lock_and_cache block from the surrounding class, method, and object... so that you don't have to!

Standalone mode is cool too, tho.

### nil_expires

You can expire nil values with a different timeout (`nil_expires`) than other values (`expires`).

## Tunables

* `LockAndCache.storage=[redis]`
* `ENV['LOCK_AND_CACHE_DEBUG']='true'` if you want some debugging output on `$stderr`

## Few dependencies

* [activesupport](https://rubygems.org/gems/activesupport) (come on, it's the bomb)
* [redis](https://github.com/redis/redis-rb)
* [redlock](https://github.com/leandromoreira/redlock-rb)

## Known issues

* In cache keys, can't distinguish {a: 1} from [[:a, 1]]

## Wishlist

* Convert most tests to use standalone mode, which is easier to understand
* Check options
* Lengthen heartbeat so it's not so sensitive
* Clarify which options are seconds or milliseconds

## Contributing

1. Fork it ( https://github.com/[my-github-username]/lock_and_cache/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

# Copyright 

Copyright 2015 Seamus Abshere
