class SimpleApp
  def call(env)
    [
      200,
      {'Content-Type' => 'text/html'},
      ['Hello World']
    ]
  end
end

run SimpleApp.new
