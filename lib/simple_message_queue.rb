require 'simple_message_queue/configuration'
require 'simple_message_queue/core_ext/string'
require 'simple_message_queue/errors'
require 'simple_message_queue/notification'
require 'aws-sdk-v1'

module SimpleMessageQueue
  class << self
    # Class Methods only available to SimpleMessageQueue
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration)

      if self.configuration.sns_notifications
        topics = ['send_message_failure']
        topics.each do |topic|
          SimpleMessageQueue::Notification::Topic.new(topic)
        end
      end

    end

  end

  def sqs
    raise SimpleMessageQueue::ConfigurationError unless SimpleMessageQueue.configuration
    raise SimpleMessageQueue::EnvironmentError unless environment_defined?
    @@sqs ||= AWS::SQS.new(:access_key_id => SimpleMessageQueue.configuration.access_key_id, :secret_access_key => SimpleMessageQueue.configuration.secret_access_key)
  end

  def queue_name
    raise SimpleMessageQueue::EnvironmentError unless environment_defined?
    if @queue_name
      @queue_name + "_#{SimpleMessageQueue.configuration.environment}"
    else
      name.underscore.gsub('/', '_') + "_#{SimpleMessageQueue.configuration.environment}"
    end
  end

  def queue
    @queue ||= sqs.queues.create(queue_name)
  end

  def count
    queue.approximate_number_of_messages
  end

   def delete_queue
    queue.delete
  end

  def exists?
    # Although there is a queue.exists? method, that is only relevant if you already have the queue stored in a variable and then delete it
    # Trying to look it up by name will either return the queue object or throw an error, hence the rescue
    true if sqs.queues.named(queue_name)
  rescue
    false
  end

  def send(message, options={})
    error_msg = nil
    response = nil
    begin
      response = queue.send_message(message, options)
    rescue => error
      error_msg = error.to_s
      full_error_msg = "There was an error when sending an item to #{queue_name} at #{DateTime.now}. Error: #{error_msg}"
      logger.error full_error_msg

      if defined?(SimpleMessageQueue.configuration.sns_notifications) && SimpleMessageQueue.configuration.sns_notifications == true
        topic = SimpleMessageQueue::Notification::Topic.new('send_message_failure')
        response = topic.send(full_error_msg, "SimpleMessageQueue: Send Message Failure")
      end
    end

    if db_logger_set?
      db_logger = Object.const_get SimpleMessageQueue.configuration.db_logger
      db_logger.create(queue_name: queue_name, action: "send", message: message, error: error_msg)
    end
    return response
  end

  def logger
    if SimpleMessageQueue.configuration.logger
      @logger = SimpleMessageQueue.configuration.logger
    else
      @logger ||= Logger.new(STDOUT)
    end
  end

  def receive
    @count = 0
    queue.poll(:idle_timeout => SimpleMessageQueue.configuration.idle_timeout, :wait_time_seconds => SimpleMessageQueue.configuration.wait_time_seconds) do |message|
      logger.info "Message received for #{queue_name}" if SimpleMessageQueue.configuration.debug
      logger.info "Message body: #{message.body}" if SimpleMessageQueue.configuration.debug
      @count += 1

      if db_logger_set?
        db_logger = Object.const_get SimpleMessageQueue.configuration.db_logger
        db_logger.create(queue_name: queue_name, action: "receive", message: message.body)
      end

      process_message(message)
    end

    @count
  end

  def process_message(message)
    raise SimpleMessageQueue::NotImplementedError.new(name)
  end

  protected

    def environment_defined?
      defined?(SimpleMessageQueue.configuration.environment)
    end

    def db_logger_set?
      !SimpleMessageQueue.configuration.db_logger.blank?
    end

end
