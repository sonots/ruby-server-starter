class MyJob
  @queue = :test

  def self.perform(params)
    puts params
  end
end
