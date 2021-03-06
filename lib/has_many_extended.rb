module HasManyExtended
  DEBUG = false

  # when included enrich the caller with class methods
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods

    # dynamicly create attributes from the join table on this side of the
    # relationship
    #
    def has_many_extended(them, opts={})
      if !opts[:through]
        raise "You must specify a through for has_many_extended"
      end

      # did the user specify what attributes belong to this side of the
      # relationship?
      #
      create_attributes = opts.delete(:attributes)
      
      # first, make sure we have many with the user-given options
      has_many them, opts

      # we are going to use the join class, so lets get one
      join_method = opts[:through]

      join_klass = nil

      # find the reflection and check for if there was a class_name set
      if (
        self.reflections.has_key? opts[:through] and
        self.reflections[opts[:through]].options.has_key? :class_name
      ) then
        join_klass = self.reflections[opts[:through]].options[:class_name]

      else
        join_klass  = opts[:through].to_s.camelize.singularize

      end
      
      RAILS_DEFAULT_LOGGER.debug("Going to check #{join_klass}") if DEBUG

      # we need an instance of self to figure out the find conditions for
      # the join class
      me       = self.new
      my_class = me.class.name
      my_id    = my_class.underscore + "_id"
      
      # when the user did not supply a list of attributes for this side of
      # the relationship; perfom automagic
      if !create_attributes
        @@hme_attributes ||= {}
        @@hme_attributes[my_class] ||= me.attribute_names

        my_attributes = @@hme_attributes[my_class]
        RAILS_DEFAULT_LOGGER.debug "#{my_class} : #{me.attribute_names.join(', ')}" if DEBUG

        # we need to know the attributes of the join class to make automagic
        # happen...
        unless @@hme_attributes[join_klass]
          join = nil; eval "join = #{join_klass}.new"
          @@hme_attributes[join_klass] ||= join.attribute_names.select { |a|
            a !~ /_id$/
          }
        end
        
        join_attributes = @@hme_attributes[join_klass]
        RAILS_DEFAULT_LOGGER.debug "#{join_klass} : #{join_attributes.join(', ')}" if DEBUG
        
        create_attributes = join_attributes - my_attributes
      end
      
      RAILS_DEFAULT_LOGGER.debug "Creating : #{create_attributes.join(', ')}" if DEBUG
      
      create_attributes.each { |attr|
        RAILS_DEFAULT_LOGGER.debug "Creating #{attr} and #{attr}= on #{my_class}" if DEBUG
        instance_eval do
          # define a getter
          define_method(attr) do |other|
            join     = nil
            other_id = other.class.name.underscore + "_id"

            join = self.send(join_method).select { |j|
              j.send(other_id) == other.id
            }.first

            return join ? join.send(attr) : nil
          end
          
          # and define a setter
          attr_is = attr.to_s
          attr_is = (attr_is += "=").to_sym          
          define_method(attr_is) do |args|
            other, value = args

            RAILS_DEFAULT_LOGGER.debug"o: #{other}, v: #{value}" if DEBUG
            
            raise(
              "Need a related object to set a value on a join class"
            ) unless other
            
            join     = nil
            other_id = other.class.name.underscore + "_id"

            eval "join = #{join_klass}.find("+
              " :first, "+
              " :conditions => {"+
              "   :#{my_id} => self.id, "+
              "   :#{other_id} => #{other.id} }"+
              ")"
            if join
              join.send(attr_is, value)
              join.save
              
            else
              raise "No such relationship"
            end
          end
        end
      }
    end
  end
end
