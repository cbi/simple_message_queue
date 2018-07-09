# Simple Message Queue

Simple Message Queue is a gem to create and receive messages from AWS's SQS. You will need an AWS account with SQS enabled in order to use Simple Message Queue.

Simple Message Queue can be used by a single application for background job processing (e.g. sending emails in the background), or by multiple applications to communicate with each other (e.g. sending data between applications).

### Setting up Simple Message Queue

In order to use Simple Message Queue in your application, you must first configure it. In order to configure Simple Message Queue, you must call a configure block and pass at least your AWS access_key_id and secret_access_key as well as the environment.

The environment variable is used to name your queues. You don't want to be using the same queue in development as in production, so the environment is required, and will be appended to your queue name (e.g. test_queue_development and test_queue_production). In a rails application you can simply use Rails.env (as shown below). If you are using Sinatra or another framework, you will probably want to use ENV['RACK_ENV'], just make sure that you set ENV['RACK_ENV'] in all of your environments or SimpleMessageQueue will throw errors.

```ruby
SimpleMessageQueue.configure do |config|
  config.access_key_id = 'your_access_key_id'
  config.secret_access_key= 'your_secret_access_key'
  config.environment = Rails.env                      # For Rails applications
  # config.environment = ENV['RACK_ENV']              # For non-Rails applications
end
```

In a rails application this is best done in an initializer. Create a file in config/initializers called simple_message_queue.rb and add the configure block. 

You can also pass in a few other variables to the configure block such as an idle_timeout and wait_time_seconds (both used only when receiving messages) as well as a logger to replace the default logger (STDOUT).

```ruby
SimpleMessageQueue.configure do |config|
  config.access_key_id = 'your_access_key_id'               # String                                              (required)
  config.secret_access_key= 'your_secret_access_key'        # String                                              (required)
  config.environment = Rails.env                            # String                                              (required)
  config.idle_timeout = 10                                  # Integer                                             (optional)
  config.wait_time_seconds = 20                             # Integer                                             (optional)
  config.logger = Logger.new('simple_message_queue.log')    # Logger                                              (optional)
  config.sns_notifications = true                           # Boolean                                             (optional)
  config.sns_notification_prefix = 'my_prefix'              # String (alphanumeric, hyphen and underscore only)   (optional)
  config.debug = false                                      # Boolean                                             (optional)
end
```

### Using Simple Message Queue

To use Simple Message Queue, you will need to start by creating a model for your queue such as TestQueue. This model can be created anywhere, although you will need to make sure that it is in a location that is loaded by your application. For rails applications it is best practice to place your queues in app/queues.

Next you will need to extend SimpleMessageQueue in your model:

```ruby
class TestQueue
  extend SimpleMessageQueue
end
```

#### Queue Naming

By default, your SQS queue will be named after the model you created and appended with the environment name (e.g. TestQueue in development will have a queue named test_queue_development). You can overwrite this in your model by adding a @queue_name variable to the class:

```ruby
class TestQueue
  extend SimpleMessageQueue

  @queue_name = 'super_awesome_queue'                       # String (alphanumeric, hyphen and underscore only)   (optional)
end
```

This will generate a queue with the name of super_awesome_queue_development in your development environment. 

**NOTE:** To prevent the same queue being used in multiple environments (which could wreak havoc with your application), the environment name is always appended to the queue_name. Although you can overwrite the queue_name method, this is a very, very bad idea (BUT if you do, please take multiple environments into account).


#### Sending Messages

In order to send a message with Simple Message Queue, simply call the following:

```ruby
TestQueue.send('my_string')
```

You can send anything you would like to the queue, but it must be a string and less than 256 KB (AWS SQS restriction). You can send a simple message, or you can send the json representation of an object. What you send is completely up to you.

#### Receiving Messages

In order to receive messages, you will need to define a process_message method for your new queue model. Since every queue will process messages differently, you will need to tell your queue how to process these messages.

```ruby
class TestQueue
  extend SimpleMessageQueue

  def self.process_message(message)
    logger.info message.body
  end
end
```

Once you have defined the process_message method, you can call TestQueue.receive to receive messages once. This will poll your queue with the idle_timeout and wait_time_seconds (either the defaults or what was defined in the configure block).

If you want to continuously receive messages (as opposed to once), you will need to set up something that will keep calling TestQueue.receive. You could create a rake task which is then called by a cron job, or you could set up a daemon.

##### Using daemons-rails gem to continuously receive messages

One of the easiest ways to continuously receive messages is to set up a daemon that will keep calling TestQueue.receive. If you are using Simple Message Queue with rails, you can use the 'daemons-rails' gem (https://github.com/mirasrael/daemons-rails). Place this in your Gemfile and bundle. Next, generate a daemon with 'rails g daemon [name]'. 2 files will be created in lib/daemons, [name]_daemon_ctl (a setup file for your daemon) and [name]_daemon.rb (which is where we will place the code to receive messages). In [name]_daemon.rb, within the while($running) block, we want to call TestQueue.receive and then have it sleep. The length we have it sleep will be the time between polling for messages.

test_queue_daemon.rb
```ruby
#!/usr/bin/env ruby

# You might want to change this
ENV["RAILS_ENV"] ||= "production"

root = File.expand_path(File.dirname(__FILE__))
root = File.dirname(root) until File.exists?(File.join(root, 'config'))
Dir.chdir(root)

require File.join(root, "config", "environment")

$running = true
Signal.trap("TERM") do 
  $running = false
end

while($running) do
  
  TestQueue.run
  sleep 60*5

end
```

This is the default [name]_daemon.rb file generated, with out code placed in the while($running) block. You can now access all of the rake tasks associated with the daemon (refer to the daemon-rails github page for these rake tasks).

**NOTE:** You will want to monitor these daemons and have something to restart them if they stop. Something like God (http://godrb.com/) or Monit (http://mmonit.com/monit/) will work nicely.

### SNS Notifications

Simple Message Queue allows you to send notifications via Amazon's SNS. Notifications will be sent when your queue fails to send a message.

In order to set up notifications, add sns_notifications = true to your config. If you would like to prefix your queues with a name, add sns_notification_prefix = 'prefix'.

```ruby
SimpleMessageQueue.configure do |config|
  ...
  config.sns_notifications = true
  config.sns_notification_prefix = 'my_prefix'
end
```

After the configure block is parsed (usually during initialization), the SNS Topics are automatically created, allowing you to subscribe to those topics before a message is ever sent. 

**Note:** Although the SNS Topics are created automatically, and messages will be sent to those topics, you will not receive any notifications until you create subscriptions to those topics. After your topics have been created, log into your AWS account and navigate to the SNS page. For each topic here, you will need to create at least one subscription in order to receive notifications.

**Note:** SNS Topics are created for each environment (similar to the queues). You will need to subscribe to the topics after each environment is initialized in order to make sure you receive messages for each environment. You can also set up different subscriptions for each environment (e.g. maybe you only want to receive email notifications in development, but would like to receive email and SMS in production).

### Logging Messages in Database
If you would like to automatically log your messages into a database table, you can do so by configuring the name of the ActiveRecord model that you would like to use.

```ruby
SimpleMessageQueue.configure do |config|
  ...
  config.db_logger = 'MyClassName'
end
```
 
The class name you pass in must include the following columns:
- queue_name: string
- action: string
- message: text
- error: string

### Single Site Communication

If you are using Simple Message Queue for background processing on a single site, all you need to do is create your model and extend SimpleMessageQueue. You will then be able to call the send and receive methods on that model.

### Multiple Site Communication

If you are using Simple Message Queue for background processing between sites you will need to take a few additional steps. You will need to create a model in each application that extends SimpleMessageQueue. Next, both of these models will need to have the same queue_name. You can do this with careful naming, or define the queue_name method as described above and give them the same name (recommended). 

**Note:** If you have multiple models receiving messages from the same queue, there is no guarantee which model will receive which message. This is why it is best to only have a single model (on a single site) receiving messages from a specific queue. If you need multiple queues, simply create multiple models with different queue_names.


## Contributing

In order to contribute to this gem, please submit a pull request with passing tests. 
In order to test locally, you will need to rename lib/config.yml.sample to lib/config.yml and add in your AWS access_key_id and secret_access_key.
