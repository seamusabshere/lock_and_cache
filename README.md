# LockAndCache

[![Build Status](https://travis-ci.org/seamusabshere/lock_and_cache.svg?branch=master)](https://travis-ci.org/seamusabshere/lock_and_cache)
[![Code Climate](https://codeclimate.com/github/seamusabshere/lock_and_cache/badges/gpa.svg)](https://codeclimate.com/github/seamusabshere/lock_and_cache)
[![Dependency Status](https://gemnasium.com/seamusabshere/lock_and_cache.svg)](https://gemnasium.com/seamusabshere/lock_and_cache)
[![Gem Version](https://badge.fury.io/rb/lock_and_cache.svg)](http://badge.fury.io/rb/lock_and_cache)
[![security](https://hakiri.io/github/seamusabshere/lock_and_cache/master.svg)](https://hakiri.io/github/seamusabshere/lock_and_cache/master)
[![Inline docs](http://inch-ci.org/github/seamusabshere/lock_and_cache.svg?branch=master)](http://inch-ci.org/github/seamusabshere/lock_and_cache)

Lock and cache using redis!

## Redlock locking

Based on [antirez's Redlock algorithm](http://redis.io/topics/distlock).

```ruby
LockAndCache.storage = Redis.new
```

It will use this redis for both locking and storing cached values.

## Convenient caching

(be sure to set up storage as above)

You put a block inside of a method:

```ruby
class Blog
  def click(arg1, arg2)
    lock_and_cache(arg1, arg2, expires: 5) do
      # do the work
    end
  end
end
```

The key will be `{ Blog, :click, $id, $arg1, $arg2 }`. In other words, it auto-detects the class, method, object id ... and you add other args if you want.

You can change the object id easily:

```ruby
class Blog
  # [...]
  # if you don't define this, it will try to call #id
  def lock_and_cache_key
    [author, title]
  end
end
```

## Tunables

* `LockAndCache.storage=[redis]`
* `LockAndCache.lock_expires=[seconds]` default is 3 days
* `LockAndCache.lock_spin=[seconds]` (how long to wait before retrying lock) default is 0.1 seconds
* `ENV['LOCK_AND_CACHE_DEBUG']='true'` if you want some debugging output on `$stderr`

## Few dependencies

* [activesupport](https://rubygems.org/gems/activesupport) (come on, it's the bomb)
* [redis](https://github.com/redis/redis-rb)
* [redlock](https://github.com/leandromoreira/redlock-rb)
* [hash_digest](https://github.com/seamusabshere/hash_digest) (which requires [murmurhash3](https://github.com/funny-falcon/murmurhash3-ruby))

## Real-world usage

<p><a href="http://faraday.io"><img src="https://s3.amazonaws.com/photos.angel.co/startups/i/175701-a63ebd1b56a401e905963c64958204d4-medium_jpg.jpg" alt="Faraday logo"/></a></p>

We use [`lock_and_cache`](https://rubygems.org/gems/lock_and_cache) for [big data-driven marketing at Faraday](http://angel.co/faraday).

## Contributing

1. Fork it ( https://github.com/[my-github-username]/lock_and_cache/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

# Copyright 

Copyright 2015 Seamus Abshere
