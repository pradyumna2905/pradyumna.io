---
title: Testing GraphQL in Rails - Part I (Mutations)
layout: post
published: true
---

Let's see how we can test a GraphQL API in a robust and modular way in Ruby on Rails. If you are not familiar with GraphQL, the [GraphQL Documentation](http://graphql.org/learn/) and [GraphQL Ruby](http://graphql-ruby.org/) are good places to start.

## Assumptions
1. Basic understanding of GraphQL terminology
2. A good understanding of Ruby/Rails
3. A Rails app setup with GraphQL (see [GraphQL Ruby](https://github.com/rmosolgo/graphql-ruby))

I'll be using `TestUnit` throughout this post which is Rails' default test framework, but the tests will look very similar in `RSpec` as well.

So, let's dive right in.

Our mutation is called `RegisterUser` which, as the name suggests, registers the user.
```ruby
# app/graphql/mutation/user_mutations.rb

module Mutations::UserMutations
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

      if user.save
        user.generate_access_token!
        user.update_tracked_fields(ctx[:request])
      end

      # Return
      {
        user: user,
        success: user.added? && user.access_token.present?,
        errors: user.errors.full_messages
      }
    }
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
  field :firstName, types.String, 'First name of the user',
    property: :first_name
  field :lastName, types.String, 'Last name of the user',
    property: :last_name
end
```

Note that I'm returning a `success` `Boolean` which essentially tells the client whether the operation (query or mutation) was successful or not. Additionally, I'm also returning an `errors` `Array` instead of using the `GraphQL` global `errors` object. The global object should be used for errors that occur specific to the GraphQL server and should not be used to deal with resource related errors (e.g. `ActiveRecord::RecordInvalid`). I also make sure these fields always return a value by stating `!types[types.String]` and `!types.Boolean`.

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

Now that we are ready to send the `POST` request to the `/graphql` endpoint, we can imitate the query we made in `graphiql`. However, instead of pasting the query/mutation inside the test file, let's abstract queries/mutations into their own module.

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

Now, in our tests, we will be able to use the above method.
```ruby
post('/graphql', params: {
  query: register_user_mutation
})
```

As you see, we've now extracted the query generation to its own module, thus making the code much more readable. Next, our goal is to implement a method to send the `variables` along with this query.

I'm going to use `factory_bot` to generate data, but you can use your preferred data generation library.

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
We need to keep in mind that GraphQL uses camel case (`firstName`, `lastName`), whereas Ruby/Rails uses snake case (`first_name`, `last_name`). Therefore, we will need to convert the attributes from the factory before using them as variables to the mutation.
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
In the method above, we are getting the user's attributes from the factory and *camelizing* them using the `transform_keys` method. We then convert the camelized hash to `JSON` and return it.

Also, instead of defaulting data to the one created by the factory, let's add the ability to pass attributes to the `register_user_mutation_variables`. 

```ruby
def register_user_mutation_variables(attrs = {})
  user_attrs = attributes_for(:user)

  # Merge the arguments
  attrs.reverse_merge!(user_attrs)

  # Camelize for GraphQL compatibility and return
  camelize_hash_keys(attrs).to_json
end
```

We can then update our `POST` call to look something like this:
```ruby
post('/graphql', params: {
  query: register_user_mutation,
  variables: register_user_mutation_variables({first_name: 'Jamie'})
})
```
GraphQL returns a JSON for any operation performed (as we saw in the `Graphiql` image above). Although it is okay to assert the entire string in the response, it will be hard to maintain.

Instead, let's create a `GraphQL::ResponseParser` class which handles responses and returns a hash.

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

Our tests will now look like this.

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

And we are done.


We need to keep in mind that in order use all the helpers we created above, we will need to `include` them from our `test_helper`.

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
