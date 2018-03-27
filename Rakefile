desc 'Create a new post with the provided name'
task :new do
  require './lib/post_creator'
  toplevel_directory = Rake.application.find_rakefile_location[1]
  PostCreator.new(toplevel_directory).create
end
