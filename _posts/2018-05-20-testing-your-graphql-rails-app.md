---
title: Testing your GraphQL Mutations in Rails
layout: post
published: true
---

Let's see how we can test GraphQL server in a robust and modular way in Ruby on Rails. If you are not familiar with GraphQL, the [GraphQL Documentation](http://graphql.org/learn/) and [GraphQL Ruby](http://graphql-ruby.org/) are good places to start.

## Assumptions
1. Basic understanding of GraphQL terminology
2. A good understanding of Ruby/Rails
3. A Rails app with GraphQL setup

Note: I'll be using `TestUnit` which is Rails' default test framework, but the tests will look exactly the same in `RSpec` as well.

I aim to keep this post focused on *testing* the GraphQL server, so let's dive right in.

Our mutation is called `RegisterUser` which, as the name suggests, registers the user and is fairly straightforward.
```ruby
# app/graphql/mutation/user_mutations.rb

module Mutations::UserMutations
  Register = GraphQL::Relay::Mutation.define do
    Register = GraphQL::Relay::Mutation.define do
    name 'RegisterUser'

    input_field :email, !types.String
    input_field :password, !types.String
    input_field :firstName, !types.String
    input_field :lastName, !types.String

    return_field :user, Types::UserType
    return_field :errors, !types[types.String]
    return_field :success, !types.Boolean

    resolve ->(_obj, inputs, ctx) {
      user = User.new(
        email: inputs[:email],
        password: inputs[:password],
        first_name: inputs[:firstName],
        last_name: inputs[:lastName]
      )

      user.generate_access_token! if user.save && user.added?

      { user: user, success: user.added?, errors: user.errors.full_messages }
    }
  end
end
```

This mutation will return a `UserType` which is defined as below:
```ruby
# app/graphql/types/user_type.rb

Types::UserType = GraphQL::ObjectType.define do
  name 'User'

  # Primary Fields
  field :id, types.ID, 'UUID of user'
  field :email, types.String, 'Email address of the user'
  field :firstName, types.String, 'First name of the user', property: :first_name
  field :lastName, types.String, 'Last name of the user', property: :last_name
end
```

Side-note: It is always preferable to return a `success` `Boolean` which essentially tells the client whether the operation (query or mutation) was successful or not. Additionally, you should also return an `errors` `Array` instead of using the `GraphQL` global `errors` object.

Once this is set up and we have exposed the mutation fields as such:
```ruby
# app/graphql/types/mutation_type.rb

Types::MutationType = GraphQL::ObjectType.define do
  name "Mutation"

  field :registerUser, field: Mutations::UserMutations::Register.field
end
```
we can go ahead and test our mutation using `graphiql` in the browser first.

<img style="height: 100%; width: 100%;" src="{{ site.baseurl }}/public/images/graphiql-1.png">

Now, let's begin writing tests. We will write integration tests which will test the queries itself. If you want to write tests to test specific `resolve` functions, [How To GraphQL](https://www.howtographql.com/) has a good example [here](https://github.com/howtographql/graphql-ruby/blob/master/test/graphql/resolvers/create_link_test.rb).

Next, let's create a basic test structure.
```ruby
# test/graphql/mutations/user_mutations_test.rb

require 'test_helper'

module Mutations
  class UserMutationsTest < ActionDispatch::IntegrationTest
    test 'register user with valid params' do
      post('/graphql', params: {
        query: 'your-query-goes-here'
      })

	  # Assertions
    end
  end
end
```
I have created `graphql` and `mutations` directories under `test` where all GraphQL tests will be. Note that I'm using the `ActionDispatch::IntegrationTest` class to write this test as we need to `POST` our query to the `/graphql` endpoint.

Now that we are ready to send the `POST` request to the `/graphql` endpoint, we can imitate the query we made in `graphiql`. However, not only it would be ugly and hard to maintain, the readability would become sub-optimal too. Instead, we are going to create support files to help us achieve clean and extensible tests.

```ruby
# test/support/graphql/mutations_helper.rb

module GraphQL
  module MutationsHelper
    def register_user_mutation(input = {})
      %(
        mutation RegisterUser(
          $firstName: String!,
          $lastName: String!,
          $email: String!,
          $password: String!,
        ) {
          registerUser(input: {
            firstName:$firstName,
            lastName:$lastName,
            email:$email,
            password:$password,
          }) {
            user {
              id
              firstName
              lastName
              email
              success
              errors
            }
          }
        }
      )
    end
  end
end
```

In our test we will use:
```ruby
post('/graphql', params: {
  query: register_user_mutation
})
```

As you see, we've now extracted the query generation to its own module, thus making the code much more readable. Next, our goal is to implement a method to send the `variables` along with this query.

We need to keep in mind that GraphQL uses camel case (`firstName`, `lastName`), whereas Ruby/Rails uses snake case (`first_name`, `last_name`). Although we can manually create JSON objects as we did in the browser, we should take advantage of `factories/fixtures`. I'm going to use `factory_bot` but you can use your preferred data generation library.

This is how the `users` `factory` will look like
```ruby
# test/factories/users.rb
FactoryBot.define do
  factory :user do
    first_name 'John'
    last_name 'Doe'
    email 'john@example.com'
    password 'secr3t'
    password_confirmation 'secr3t'
  end
end
```

In the method below, we are basically getting the user's attributes from the factory and *camelizing* them using the `transform_keys` method. We then convert the camelized hash to `JSON` and return it.
```ruby
# test/support/graphql/mutation_variables.rb

module GraphQL
  module MutationVariables
    def register_user_mutation_variables
      attrs = attributes_for(:user)

      # Camelize for GraphQL compatibility and return
      camelize_hash_keys(attrs).to_json
    end

    def camelize_hash_keys(hash)
      raise unless hash.is_a?(Hash)

      hash.transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end
end
```

This is good, but we need to take it a step further. We are currently only depending on the user's factory for test data. For example, there is no way for us to modify the first_name of the user using `register_user_mutation_variables` method.

Additionally, since we always keep factories valid (i.e. we don't have any validation errors in factories), testing an invalid scenario would mean manually creating invalid data like `user=User.new(first_name: '', last_name: 'Doe')`.

Instead, we can just pass user attributes to the `register_user_mutation_variables` method.  

```ruby
def register_user_mutation_variables(attrs = {})
  user_attrs = attributes_for(:user)

  # Merge the arguments
  attrs.reverse_merge!(user_attrs)

  # Camelize for GraphQL compatibility and return
  camelize_hash_keys(attrs).to_json
end
```

We have to honor arguments that are passed in and merge them with the factory attributes so that we don't have to pass in all the attributes all the time.

Now that this is done, we can update our `Post` call test case to look something like this:
```ruby
post('/graphql', params: {
  query: register_user_mutation,
  variables: register_user_mutation_variables({first_name: 'Jamie'})
})
```

Let's see how we can make our assertions now.

GraphQL returns a JSON for any operation performed (as we saw in the `Graphiql` image above). Although it is okay to assert the entire string in the response, it will be hard to maintain.

```ruby
...
```
Instead, let's create a `GraphQL::ResponseParser` class which handles responses and returns a hash which will be easier to test. Also, note that we don't have to do string comparison here between expected and actual responses.

```ruby
# test/support/graphql/response_parser.rb

module GraphQL
  module ResponseParser
    def parse_graphql_response(original_response)
      JSON.parse(original_response).delete("data")
    end
  end
end
```

That's it. Now we can just use this parser to assert responses in our tests. Our tests will now look like this.

```ruby
# test/graphql/mutations/user_mutations_test.rb

require 'test_helper'

module Mutations
  class UserMutationsTest < ActionDispatch::IntegrationTest
    test 'register user with valid params' do
      post('/graphql', params: {
        query: register_user_mutation,
        variables: register_user_mutation_variables({first_name: 'Jamie'})
      })

      @json_response = parse_graphql_response(response.body)

	     assert_equal true, @json_response.dig("registerUser", "success")
       assert_equal 'Jamie', @json_response.dig("registerUser", "user", "firstName")
    end
  end
end
```

And we are done. We need to keep in mind that in order use all the helpers, we will need to `include` them from our `test_helper`.

```ruby
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all
  include FactoryBot::Syntax::Methods

  Dir[Rails.root.join('test/support/**/*.rb')].each { |f| require f }

  include GraphQL::MutationsHelper
  include GraphQL::ResponseParser
  include GraphQL::MutationVariables
end
```

Peace.
