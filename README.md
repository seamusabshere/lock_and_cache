# LockAndCache

[![Build Status](https://travis-ci.org/seamusabshere/lock_and_cache.svg?branch=master)](https://travis-ci.org/seamusabshere/lock_and_cache)
[![Code Climate](https://codeclimate.com/github/seamusabshere/lock_and_cache/badges/gpa.svg)](https://codeclimate.com/github/seamusabshere/lock_and_cache)
[![Dependency Status](https://gemnasium.com/seamusabshere/lock_and_cache.svg)](https://gemnasium.com/seamusabshere/lock_and_cache)
[![Gem Version](https://badge.fury.io/rb/lock_and_cache.svg)](http://badge.fury.io/rb/lock_and_cache)
[![Security](https://hakiri.io/github/seamusabshere/lock_and_cache/master.svg)](https://hakiri.io/github/seamusabshere/lock_and_cache/master)
[![Inline docs](http://inch-ci.org/github/seamusabshere/lock_and_cache.svg?branch=master)](http://inch-ci.org/github/seamusabshere/lock_and_cache)

Lock and cache using redis!

## Sponsor

<p><a href="http://faraday.io"><img src="https://s3.amazonaws.com/photos.angel.co/startups/i/175701-a63ebd1b56a401e905963c64958204d4-medium_jpg.jpg" alt="Faraday logo"/></a></p>

We use [`lock_and_cache`](https://rubygems.org/gems/lock_and_cache) for [big data-driven marketing at Faraday](http://faraday.io).

## Theory

`lock_and_cache`...

1. returns cached value if found
2. acquires a lock
3. returns cached value if found (just in case it was calculated while we were waiting for a lock)
4. calculates and caches the value
5. releases the lock
6. returns the value

As you can see, most caching libraries only take care of (1) and (4).

## Practice

### Locking

Based on [antirez's Redlock algorithm](http://redis.io/topics/distlock).

Above and beyond Redlock, a 2-second heartbeat is used that will clear the lock if a process is killed. This is implemented using lock extensions.

```ruby
LockAndCache.storage = Redis.new
```

It will use this redis for both locking and storing cached values.

### Caching

(be sure to set up storage as above)

#### Standalone mode

```ruby
LockAndCache.lock_and_cache('stock_price') do
  # get yer stock quote
end
```

But that's probably not very useful without parameters

```ruby
LockAndCache.lock_and_cache('stock_price', company: 'MSFT', date: '2015-05-05') do
  # get yer stock quote
end
```

And you probably want an expiry

```ruby
LockAndCache.lock_and_cache('stock_price', {company: 'MSFT', date: '2015-05-05'}, expires: 10) do
  # get yer stock quote
end
```

Note how we separated options (`{expires: 10}`) from a hash that is part of the cache key (`{company: 'MSFT', date: '2015-05-05'}`).

You can clear a cache:

```ruby
LockAndCache.lock_and_cache('stock_price', company: 'MSFT', date: '2015-05-05')
```

One other crazy thing: let's say you want to check more often if the external stock price service returned nil

```ruby
LockAndCache.lock_and_cache('stock_price', {company: 'MSFT', date: '2015-05-05'}, expires: 10, nil_expires: 1) do
  # get yer stock quote
end
```

#### Context mode

"Context mode" simply adds the class name, method name, and context key (the results of `#id` or `#lock_and_cache_key`) of the caller to the cache key.

(This gem evolved from https://github.com/seamusabshere/cache_method, where you always cached a method call...)

```ruby
class Stock
  include LockAndCache

  def initialize(ticker_symbol)
    [...]
  end

  def price(date)
    lock_and_cache(date, expires: 10) do # <------ see how the cache key depends on the method args?
      # do the work
    end
  end

  def lock_and_cache_key # <---------- if you don't define this, it will try to call #id
    ticker_symbol
  end
end
```

The key will be `{ StockQuote, :get, $id, $date, }`. In other words, it auto-detects the class, method, context key ... and you add other args if you want.

Here's how to clear a cache in context mode:

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
