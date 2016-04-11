require 'spec_helper'

class KeyTestId
  def id
    'id'
  end
end
class KeyTestLockAndCacheKey
  def lock_and_cache_key
    'lock_and_cache_key'
  end
end
describe LockAndCache::Key do
  describe 'parts' do
    it "has a known issue differentiating between {a: 1} and [[:a, 1]]" do
      expect(described_class.new(a: 1).send(:parts)).to eq(described_class.new([[:a, 1]]).send(:parts))
    end
    
    {
      [1]                                                => [1],
      ["you"]                                            => ['you'],
      [["you"]]                                          => [['you']],
      [["you"], "person"]                                => [["you"], "person"],
      [["you"], {:silly=>:person}]                       => [["you"], [[:silly, :person]] ],
      { hi: 'you' }                                      => [[:hi, "you"]],
      [KeyTestId.new]                                    => ['id'],
      [[KeyTestId.new]]                                  => [['id']],
      { a: KeyTestId.new }                               => [[:a, "id"]],
      [{ a: KeyTestId.new }]                             => [[[:a, "id"]]],
      [[{ a: KeyTestId.new }]]                           => [[ [[:a, "id"]] ]],
      [[{ a: [ KeyTestId.new ] }]]                       => [[[[:a, ["id"]]]]],
      [[{ a: { b: KeyTestId.new } }]]                    => [[ [[ :a, [[:b, "id"]] ]] ]],
      [[{ a: { b: [ KeyTestId.new ] } }]]                => [[ [[ :a, [[:b, ["id"]]] ]] ]],
      [KeyTestLockAndCacheKey.new]                       => ['lock_and_cache_key'],
      [[KeyTestLockAndCacheKey.new]]                     => [['lock_and_cache_key']],
      { a: KeyTestLockAndCacheKey.new }                  => [[:a, "lock_and_cache_key"]],
      [{ a: KeyTestLockAndCacheKey.new }]                => [[[:a, "lock_and_cache_key"]]],
      [[{ a: KeyTestLockAndCacheKey.new }]]              => [[ [[:a, "lock_and_cache_key"]] ]],
      [[{ a: [ KeyTestLockAndCacheKey.new ] }]]          => [[[[:a, ["lock_and_cache_key"]]]]],
      [[{ a: { b: KeyTestLockAndCacheKey.new } }]]       => [[ [[ :a, [[:b, "lock_and_cache_key"]] ]] ]],
      [[{ a: { b: [ KeyTestLockAndCacheKey.new ] } }]]   => [[ [[ :a, [[:b, ["lock_and_cache_key"]]] ]] ]],
    }.each do |i, o|
      it "turns #{i} into #{o}" do
        expect(described_class.new(i).send(:parts)).to eq(o)
      end
    end
  end
end
