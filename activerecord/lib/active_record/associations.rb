require 'active_record/associations/association_proxy'
require 'active_record/associations/association_collection'
require 'active_record/associations/belongs_to_association'
require 'active_record/associations/has_one_association'
require 'active_record/associations/has_many_association'
require 'active_record/associations/has_and_belongs_to_many_association'
require 'active_record/deprecated_associations'

module ActiveRecord
  module Associations # :nodoc:
    def self.append_features(base)
      super
      base.extend(ClassMethods)
    end

    # Clears out the association cache 
    def clear_association_cache #:nodoc:
      self.class.reflect_on_all_associations.to_a.each do |assoc|
        instance_variable_set "@#{assoc.name}", nil
      end
    end
    
    # Associations are a set of macro-like class methods for tying objects together through foreign keys. They express relationships like 
    # "Project has one Project Manager" or "Project belongs to a Portfolio". Each macro adds a number of methods to the class which are 
    # specialized according to the collection or association symbol and the options hash. It works much the same was as Ruby's own attr* 
    # methods. Example:
    #
    #   class Project < ActiveRecord::Base
    #     belongs_to              :portfolio
    #     has_one                 :project_manager 
    #     has_many                :milestones
    #     has_and_belongs_to_many :categories
    #   end
    #
    # The project class now has the following methods (and more) to ease the traversal and manipulation of its relationships:
    # * <tt>Project#portfolio, Project#portfolio=(portfolio), Project#portfolio.nil?</tt>
    # * <tt>Project#project_manager, Project#project_manager=(project_manager), Project#project_manager.nil?,</tt>
    # * <tt>Project#milestones.empty?, Project#milestones.size, Project#milestones, Project#milestones<<(milestone),</tt>
    #   <tt>Project#milestones.delete(milestone), Project#milestones.find(milestone_id), Project#milestones.find_all(conditions),</tt>
    #   <tt>Project#milestones.build, Project#milestones.create</tt>
    # * <tt>Project#categories.empty?, Project#categories.size, Project#categories, Project#categories<<(category1),</tt>
    #   <tt>Project#categories.delete(category1)</tt>
    #
    # == Example
    #
    # link:../../examples/associations.png
    #
    # == Is it belongs_to or has_one?
    #
    # Both express a 1-1 relationship, the difference is mostly where to place the foreign key, which goes on the table for the class
    # saying belongs_to. Example:
    #
    #   class Post < ActiveRecord::Base
    #     has_one :author
    #   end
    #
    #   class Author < ActiveRecord::Base
    #     belongs_to :post
    #   end
    #
    # The tables for these classes could look something like:
    #
    #   CREATE TABLE posts (
    #     id int(11) NOT NULL auto_increment,
    #     title varchar default NULL,
    #     PRIMARY KEY  (id)
    #   )
    #
    #   CREATE TABLE authors (
    #     id int(11) NOT NULL auto_increment,
    #     post_id int(11) default NULL,
    #     name varchar default NULL,
    #     PRIMARY KEY  (id)
    #   )
    #
    # == Unsaved objects and associations
    #
    # You can manipulate objects and associations before they are saved to the database, but there is some special behaviour you should be
    # aware of, mostly involving the saving of associated objects.
    #
    # === One-to-one associations
    #
    # * Assigning an object to a has_one association automatically saves that object, and the object being replaced (if there is one), in
    #   order to update their primary keys - except if the parent object is unsaved (new_record? == true).
    # * If either of these saves fail (due to one of the objects being invalid) the assignment statement returns false and the assignment
    #   is cancelled.
    # * If you wish to assign an object to a has_one association without saving it, use the #association.build method (documented below).
    # * Assigning an object to a belongs_to association does not save the object, since the foreign key field belongs on the parent. It does
    #   not save the parent either.
    #
    # === Collections
    #
    # * Adding an object to a collection (has_many or has_and_belongs_to_many) automatically saves that object, except if the parent object
    #   (the owner of the collection) is not yet stored in the database.
    # * If saving any of the objects being added to a collection (via #push or similar) fails, then #push returns false.
    # * You can add an object to a collection without automatically saving it by using the #collection.build method (documented below).
    # * All unsaved (new_record? == true) members of the collection are automatically saved when the parent is saved.
    #
    # == Caching
    #
    # All of the methods are built on a simple caching principle that will keep the result of the last query around unless specifically
    # instructed not to. The cache is even shared across methods to make it even cheaper to use the macro-added methods without 
    # worrying too much about performance at the first go. Example:
    #
    #   project.milestones             # fetches milestones from the database
    #   project.milestones.size        # uses the milestone cache
    #   project.milestones.empty?      # uses the milestone cache
    #   project.milestones(true).size  # fetches milestones from the database
    #   project.milestones             # uses the milestone cache
    #
    # == Eager loading of associations
    #
    # Eager loading is a way to find objects of a certain class and a number of named associations along with it in a single SQL call. This is
    # one of the easiest ways of to prevent the dreaded 1+N problem in which fetching 100 posts that each needs to display their author
    # triggers 101 database queries. Through the use of eager loading, the 101 queries can be reduced to 1. Example:
    #
    #   class Post < ActiveRecord::Base
    #     belongs_to :author
    #     has_many   :comments
    #   end
    #
    # Consider the following loop using the class above:
    #
    #   for post in Post.find(:all, :limit => 100)
    #     puts "Post:            " + post.title
    #     puts "Written by:      " + post.author.name
    #     puts "Last comment on: " + post.comments.first.created_on
    #   end 
    #
    # To iterate over these one hundred posts, we'll generate 201 database queries. Let's first just optimize it for retrieving the author:
    #
    #   for post in Post.find(:all, :limit => 100, :include => :author)
    #
    # This references the name of the belongs_to association that also used the :author symbol, so the find will now weave in a join something
    # like this: LEFT OUTER JOIN authors ON authors.id = posts.author_id. Doing so will cut down the number of queries from 201 to 101.
    #
    # We can improve upon the situation further by referencing both associations in the finder with:
    #
    #   for post in Post.find(:all, :limit => 100, :include => [ :author, :comments ])
    #
    # That'll add another join along the lines of: LEFT OUTER JOIN comments ON comments.post_id = posts.id. And we'll be down to 1 query.
    # But that shouldn't fool you to think that you can pull out huge amounts of data with no performance penalty just because you've reduced
    # the number of queries. The database still needs to send all the data to Active Record and it still needs to be processed. So its no
    # catch-all for performance problems, but its a great way to cut down on the number of queries in a situation as the one described above.
    #
    # == Modules
    #
    # By default, associations will look for objects within the current module scope. Consider:
    #
    #   module MyApplication
    #     module Business
    #       class Firm < ActiveRecord::Base
    #          has_many :clients
    #        end
    #
    #       class Company < ActiveRecord::Base; end
    #     end
    #   end
    #
    # When Firm#clients is called, it'll in turn call <tt>MyApplication::Business::Company.find(firm.id)</tt>. If you want to associate
    # with a class in another module scope this can be done by specifying the complete class name, such as:
    #
    #   module MyApplication
    #     module Business
    #       class Firm < ActiveRecord::Base; end
    #     end
    #
    #     module Billing
    #       class Account < ActiveRecord::Base
    #         belongs_to :firm, :class_name => "MyApplication::Business::Firm"
    #       end
    #     end
    #   end
    #
    # == Type safety with ActiveRecord::AssociationTypeMismatch
    #
    # If you attempt to assign an object to an association that doesn't match the inferred or specified <tt>:class_name</tt>, you'll
    # get a ActiveRecord::AssociationTypeMismatch.
    #
    # == Options
    #
    # All of the association macros can be specialized through options which makes more complex cases than the simple and guessable ones
    # possible.
    module ClassMethods
      # Adds the following methods for retrieval and query of collections of associated objects.
      # +collection+ is replaced with the symbol passed as the first argument, so 
      # <tt>has_many :clients</tt> would add among others <tt>clients.empty?</tt>.
      # * <tt>collection(force_reload = false)</tt> - returns an array of all the associated objects.
      #   An empty array is returned if none are found.
      # * <tt>collection<<(object, ...)</tt> - adds one or more objects to the collection by setting their foreign keys to the collection's primary key.
      # * <tt>collection.delete(object, ...)</tt> - removes one or more objects from the collection by setting their foreign keys to NULL.  
      #   This will also destroy the objects if they're declared as belongs_to and dependent on this model.
      # * <tt>collection.clear</tt> - removes every object from the collection. This does not destroy the objects.
      # * <tt>collection.empty?</tt> - returns true if there are no associated objects.
      # * <tt>collection.size</tt> - returns the number of associated objects.
      # * <tt>collection.find(id)</tt> - finds an associated object responding to the +id+ and that
      #   meets the condition that it has to be associated with this object.
      # * <tt>collection.find_all(conditions = nil, orderings = nil, limit = nil, joins = nil)</tt> - finds all associated objects responding 
      #   criteria mentioned (like in the standard find_all) and that meets the condition that it has to be associated with this object.
      # * <tt>collection.build(attributes = {})</tt> - returns a new object of the collection type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key but has not yet been saved. *Note:* This only works if an 
      #   associated object already exists, not if its nil!
      # * <tt>collection.create(attributes = {})</tt> - returns a new object of the collection type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key and that has already been saved (if it passed the validation).
      #   *Note:* This only works if an associated object already exists, not if its nil!
      #
      # Example: A Firm class declares <tt>has_many :clients</tt>, which will add:
      # * <tt>Firm#clients</tt> (similar to <tt>Clients.find_all "firm_id = #{id}"</tt>)
      # * <tt>Firm#clients<<</tt>
      # * <tt>Firm#clients.delete</tt>
      # * <tt>Firm#clients.clear</tt>
      # * <tt>Firm#clients.empty?</tt> (similar to <tt>firm.clients.size == 0</tt>)
      # * <tt>Firm#clients.size</tt> (similar to <tt>Client.count "firm_id = #{id}"</tt>)
      # * <tt>Firm#clients.find</tt> (similar to <tt>Client.find_on_conditions(id, "firm_id = #{id}")</tt>)
      # * <tt>Firm#clients.find_all</tt> (similar to <tt>Client.find_all "firm_id = #{id}"</tt>)
      # * <tt>Firm#clients.build</tt> (similar to <tt>Client.new("firm_id" => id)</tt>)
      # * <tt>Firm#clients.create</tt> (similar to <tt>c = Client.new("client_id" => id); c.save; c</tt>)
      # The declaration can also include an options hash to specialize the behavior of the association.
      # 
      # Options are:
      # * <tt>:class_name</tt>  - specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_many :products</tt> will by default be linked to the +Product+ class, but
      #   if the real class name is +SpecialProduct+, you'll have to specify it with this option.
      # * <tt>:conditions</tt>  - specify the conditions that the associated objects must meet in order to be included as a "WHERE"
      #   sql fragment, such as "price > 5 AND name LIKE 'B%'".
      # * <tt>:order</tt>       - specify the order in which the associated objects are returned as a "ORDER BY" sql fragment,
      #   such as "last_name, first_name DESC"
      # * <tt>:foreign_key</tt> - specify the foreign key used for the association. By default this is guessed to be the name
      #   of this class in lower-case and "_id" suffixed. So a +Person+ class that makes a has_many association will use "person_id"
      #   as the default foreign_key.
      # * <tt>:dependent</tt>   - if set to true all the associated object are destroyed alongside this object.
      #   May not be set if :exclusively_dependent is also set.
      # * <tt>:exclusively_dependent</tt>   - if set to true all the associated object are deleted in one SQL statement without having their
      #   before_destroy callback run. This should only be used on associations that depend solely on this class and don't need to do any
      #   clean-up in before_destroy. The upside is that it's much faster, especially if there's a counter_cache involved.
      #   May not be set if :dependent is also set.
      # * <tt>:finder_sql</tt>  - specify a complete SQL statement to fetch the association. This is a good way to go for complex
      #   associations that depends on multiple tables. Note: When this option is used, +find_in_collection+ is _not_ added.
      # * <tt>:counter_sql</tt>  - specify a complete SQL statement to fetch the size of the association. If +:finder_sql+ is
      #   specified but +:counter_sql+, +:counter_sql+ will be generated by replacing SELECT ... FROM with SELECT COUNT(*) FROM.
      #
      # Option examples:
      #   has_many :comments, :order => "posted_on"
      #   has_many :people, :class_name => "Person", :conditions => "deleted = 0", :order => "name"
      #   has_many :tracks, :order => "position", :dependent => true
      #   has_many :subscribers, :class_name => "Person", :finder_sql =>
      #       'SELECT DISTINCT people.* ' +
      #       'FROM people p, post_subscriptions ps ' +
      #       'WHERE ps.post_id = #{id} AND ps.person_id = p.id ' +
      #       'ORDER BY p.first_name'
      def has_many(association_id, options = {})
        validate_options([ :foreign_key, :class_name, :exclusively_dependent, :dependent, :conditions, :order, :finder_sql, :counter_sql ], options.keys)
        association_name, association_class_name, association_class_primary_key_name =
              associate_identification(association_id, options[:class_name], options[:foreign_key])
 
        require_association_class(association_class_name)

        if options[:dependent] and options[:exclusively_dependent]
          raise ArgumentError, ':dependent and :exclusively_dependent are mutually exclusive options.  You may specify one or the other.' # ' ruby-mode
        # See HasManyAssociation#delete_records.  Dependent associations
        # delete children, otherwise foreign key is set to NULL.
        elsif options[:dependent]
          module_eval "before_destroy '#{association_name}.each { |o| o.destroy }'"
        elsif options[:exclusively_dependent]
          module_eval "before_destroy { |record| #{association_class_name}.delete_all(%(#{association_class_primary_key_name} = \#{record.quoted_id})) }"
        end

        add_multiple_associated_save_callbacks(association_name)

        collection_accessor_methods(association_name, association_class_name, association_class_primary_key_name, options, HasManyAssociation)
        
        # deprecated api
        deprecated_collection_count_method(association_name)
        deprecated_add_association_relation(association_name)
        deprecated_remove_association_relation(association_name)
        deprecated_has_collection_method(association_name)
        deprecated_find_in_collection_method(association_name)
        deprecated_find_all_in_collection_method(association_name)
        deprecated_collection_create_method(association_name)
        deprecated_collection_build_method(association_name)
      end

      # Adds the following methods for retrieval and query of a single associated object.
      # +association+ is replaced with the symbol passed as the first argument, so 
      # <tt>has_one :manager</tt> would add among others <tt>manager.nil?</tt>.
      # * <tt>association(force_reload = false)</tt> - returns the associated object. Nil is returned if none is found.
      # * <tt>association=(associate)</tt> - assigns the associate object, extracts the primary key, sets it as the foreign key, 
      #   and saves the associate object.
      # * <tt>association.nil?</tt> - returns true if there is no associated object.
      # * <tt>build_association(attributes = {})</tt> - returns a new object of the associated type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key but has not yet been saved. Note: This ONLY works if
      #   an association already exists. It will NOT work if the association is nil.
      # * <tt>create_association(attributes = {})</tt> - returns a new object of the associated type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key and that has already been saved (if it passed the validation).
      #
      # Example: An Account class declares <tt>has_one :beneficiary</tt>, which will add:
      # * <tt>Account#beneficiary</tt> (similar to <tt>Beneficiary.find_first "account_id = #{id}"</tt>)
      # * <tt>Account#beneficiary=(beneficiary)</tt> (similar to <tt>beneficiary.account_id = account.id; beneficiary.save</tt>)
      # * <tt>Account#beneficiary.nil?</tt>
      # * <tt>Account#build_beneficiary</tt> (similar to <tt>Beneficiary.new("account_id" => id)</tt>)
      # * <tt>Account#create_beneficiary</tt> (similar to <tt>b = Beneficiary.new("account_id" => id); b.save; b</tt>)
      #
      # The declaration can also include an options hash to specialize the behavior of the association.
      # 
      # Options are:
      # * <tt>:class_name</tt>  - specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_one :manager</tt> will by default be linked to the +Manager+ class, but
      #   if the real class name is +Person+, you'll have to specify it with this option.
      # * <tt>:conditions</tt>  - specify the conditions that the associated object must meet in order to be included as a "WHERE"
      #   sql fragment, such as "rank = 5".
      # * <tt>:order</tt>       - specify the order from which the associated object will be picked at the top. Specified as
      #    an "ORDER BY" sql fragment, such as "last_name, first_name DESC"
      # * <tt>:dependent</tt>   - if set to true, the associated object is destroyed when this object is. It's also destroyed if another
      #   association is assigned.
      # * <tt>:foreign_key</tt> - specify the foreign key used for the association. By default this is guessed to be the name
      #   of this class in lower-case and "_id" suffixed. So a +Person+ class that makes a has_one association will use "person_id"
      #   as the default foreign_key.
      #
      # Option examples:
      #   has_one :credit_card, :dependent => true
      #   has_one :last_comment, :class_name => "Comment", :order => "posted_on"
      #   has_one :project_manager, :class_name => "Person", :conditions => "role = 'project_manager'"
      def has_one(association_id, options = {})
        validate_options([ :class_name, :foreign_key, :remote, :conditions, :order, :dependent, :counter_cache ], options.keys)

        association_name, association_class_name, association_class_primary_key_name =
            associate_identification(association_id, options[:class_name], options[:foreign_key], false)

        require_association_class(association_class_name)

        module_eval do
          after_save <<-EOF
            association = instance_variable_get("@#{association_name}")
            unless association.nil?
              association["#{association_class_primary_key_name}"] = id
              association.save(true)
              association.send(:construct_sql)
            end
          EOF
        end
      
        association_accessor_methods(association_name, association_class_name, association_class_primary_key_name, options, HasOneAssociation)
        association_constructor_method(:build, association_name, association_class_name, association_class_primary_key_name, options, HasOneAssociation)
        association_constructor_method(:create, association_name, association_class_name, association_class_primary_key_name, options, HasOneAssociation)
        
        module_eval "before_destroy '#{association_name}.destroy unless #{association_name}.nil?'" if options[:dependent]

        # deprecated api
        deprecated_has_association_method(association_name)
        deprecated_association_comparison_method(association_name, association_class_name)
      end

      # Adds the following methods for retrieval and query for a single associated object that this object holds an id to.
      # +association+ is replaced with the symbol passed as the first argument, so 
      # <tt>belongs_to :author</tt> would add among others <tt>author.nil?</tt>.
      # * <tt>association(force_reload = false)</tt> - returns the associated object. Nil is returned if none is found.
      # * <tt>association=(associate)</tt> - assigns the associate object, extracts the primary key, and sets it as the foreign key.
      # * <tt>association.nil?</tt> - returns true if there is no associated object.
      # * <tt>build_association(attributes = {})</tt> - returns a new object of the associated type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key but has not yet been saved.
      # * <tt>create_association(attributes = {})</tt> - returns a new object of the associated type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key and that has already been saved (if it passed the validation).
      #
      # Example: A Post class declares <tt>belongs_to :author</tt>, which will add:
      # * <tt>Post#author</tt> (similar to <tt>Author.find(author_id)</tt>)
      # * <tt>Post#author=(author)</tt> (similar to <tt>post.author_id = author.id</tt>)
      # * <tt>Post#author?</tt> (similar to <tt>post.author == some_author</tt>)
      # * <tt>Post#author.nil?</tt>
      # * <tt>Post#build_author</tt> (similar to <tt>Author.new("post_id" => id)</tt>)
      # * <tt>Post#create_author</tt> (similar to <tt>b = Author.new("post_id" => id); b.save; b</tt>)
      # The declaration can also include an options hash to specialize the behavior of the association.
      # 
      # Options are:
      # * <tt>:class_name</tt>  - specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_one :author</tt> will by default be linked to the +Author+ class, but
      #   if the real class name is +Person+, you'll have to specify it with this option.
      # * <tt>:conditions</tt>  - specify the conditions that the associated object must meet in order to be included as a "WHERE"
      #   sql fragment, such as "authorized = 1".
      # * <tt>:order</tt>       - specify the order from which the associated object will be picked at the top. Specified as
      #   an "ORDER BY" sql fragment, such as "last_name, first_name DESC"
      # * <tt>:foreign_key</tt> - specify the foreign key used for the association. By default this is guessed to be the name
      #   of the associated class in lower-case and "_id" suffixed. So a +Person+ class that makes a belongs_to association to a
      #   +Boss+ class will use "boss_id" as the default foreign_key.
      # * <tt>:counter_cache</tt> - caches the number of belonging objects on the associate class through use of increment_counter 
      #   and decrement_counter. The counter cache is incremented when an object of this class is created and decremented when it's
      #   destroyed. This requires that a column named "#{table_name}_count" (such as comments_count for a belonging Comment class)
      #   is used on the associate class (such as a Post class).
      #
      # Option examples:
      #   belongs_to :firm, :foreign_key => "client_of"
      #   belongs_to :author, :class_name => "Person", :foreign_key => "author_id"
      #   belongs_to :valid_coupon, :class_name => "Coupon", :foreign_key => "coupon_id", 
      #              :conditions => 'discounts > #{payments_count}'
      def belongs_to(association_id, options = {})
        validate_options([ :class_name, :foreign_key, :remote, :conditions, :order, :dependent, :counter_cache ], options.keys)

        association_name, association_class_name, class_primary_key_name =
            associate_identification(association_id, options[:class_name], options[:foreign_key], false)

        require_association_class(association_class_name)

        association_class_primary_key_name = options[:foreign_key] || Inflector.underscore(Inflector.demodulize(association_class_name)) + "_id"

        association_accessor_methods(association_name, association_class_name, association_class_primary_key_name, options, BelongsToAssociation)
        association_constructor_method(:build, association_name, association_class_name, association_class_primary_key_name, options, BelongsToAssociation)
        association_constructor_method(:create, association_name, association_class_name, association_class_primary_key_name, options, BelongsToAssociation)

        module_eval do
          before_save <<-EOF
            association = instance_variable_get("@#{association_name}")
            if not association.nil? and association.new_record?
              association.save(true)
              self["#{association_class_primary_key_name}"] = association.id
              association.send(:construct_sql)
            end
          EOF
        end
      
        if options[:counter_cache]
          module_eval(
            "after_create '#{association_class_name}.increment_counter(\"#{self.to_s.underscore.pluralize + "_count"}\", #{association_class_primary_key_name})" +
            " unless #{association_name}.nil?'"
          )

          module_eval(
            "before_destroy '#{association_class_name}.decrement_counter(\"#{self.to_s.underscore.pluralize + "_count"}\", #{association_class_primary_key_name})" +
            " unless #{association_name}.nil?'"
          )          
        end

        # deprecated api
        deprecated_has_association_method(association_name)
        deprecated_association_comparison_method(association_name, association_class_name)
      end

      # Associates two classes via an intermediate join table.  Unless the join table is explicitly specified as
      # an option, it is guessed using the lexical order of the class names. So a join between Developer and Project
      # will give the default join table name of "developers_projects" because "D" outranks "P".
      #
      # Any additional fields added to the join table will be placed as attributes when pulling records out through
      # has_and_belongs_to_many associations. This is helpful when have information about the association itself
      # that you want available on retrieval. Note that any fields in the join table will override matching field names
      # in the two joined tables. As a consequence, having an "id" field in the join table usually has the undesirable
      # result of clobbering the "id" fields in either of the other two tables.
      # 
      #
      # Adds the following methods for retrieval and query.
      # +collection+ is replaced with the symbol passed as the first argument, so 
      # <tt>has_and_belongs_to_many :categories</tt> would add among others <tt>categories.empty?</tt>.
      # * <tt>collection(force_reload = false)</tt> - returns an array of all the associated objects.
      #   An empty array is returned if none is found.
      # * <tt>collection<<(object, ...)</tt> - adds one or more objects to the collection by creating associations in the join table 
      #   (collection.push and collection.concat are aliases to this method).
      # * <tt>collection.push_with_attributes(object, join_attributes)</tt> - adds one to the collection by creating an association in the join table that
      #   also holds the attributes from <tt>join_attributes</tt> (should be a hash with the column names as keys). This can be used to have additional
      #   attributes on the join, which will be injected into the associated objects when they are retrieved through the collection.
      #   (collection.concat_with_attributes is an alias to this method).
      # * <tt>collection.delete(object, ...)</tt> - removes one or more objects from the collection by removing their associations from the join table.  
      #   This does not destroy the objects.
      # * <tt>collection.clear</tt> - removes every object from the collection. This does not destroy the objects.
      # * <tt>collection.empty?</tt> - returns true if there are no associated objects.
      # * <tt>collection.size</tt> - returns the number of associated objects.
      # * <tt>collection.find(id)</tt> - finds an associated object responding to the +id+ and that
      #   meets the condition that it has to be associated with this object.
      #
      # Example: An Developer class declares <tt>has_and_belongs_to_many :projects</tt>, which will add:
      # * <tt>Developer#projects</tt>
      # * <tt>Developer#projects<<</tt>
      # * <tt>Developer#projects.push_with_attributes</tt>
      # * <tt>Developer#projects.delete</tt>
      # * <tt>Developer#projects.clear</tt>
      # * <tt>Developer#projects.empty?</tt>
      # * <tt>Developer#projects.size</tt>
      # * <tt>Developer#projects.find(id)</tt>
      # The declaration may include an options hash to specialize the behavior of the association.
      # 
      # Options are:
      # * <tt>:class_name</tt> - specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_and_belongs_to_many :projects</tt> will by default be linked to the 
      #   +Project+ class, but if the real class name is +SuperProject+, you'll have to specify it with this option.
      # * <tt>:join_table</tt> - specify the name of the join table if the default based on lexical order isn't what you want.
      #   WARNING: If you're overwriting the table name of either class, the table_name method MUST be declared underneath any
      #   has_and_belongs_to_many declaration in order to work.
      # * <tt>:foreign_key</tt> - specify the foreign key used for the association. By default this is guessed to be the name
      #   of this class in lower-case and "_id" suffixed. So a +Person+ class that makes a has_and_belongs_to_many association
      #   will use "person_id" as the default foreign_key.
      # * <tt>:association_foreign_key</tt> - specify the association foreign key used for the association. By default this is
      #   guessed to be the name of the associated class in lower-case and "_id" suffixed. So the associated class is +Project+
      #   that makes a has_and_belongs_to_many association will use "project_id" as the default association foreign_key.
      # * <tt>:conditions</tt>  - specify the conditions that the associated object must meet in order to be included as a "WHERE"
      #   sql fragment, such as "authorized = 1".
      # * <tt>:order</tt> - specify the order in which the associated objects are returned as a "ORDER BY" sql fragment, such as "last_name, first_name DESC"
      # * <tt>:uniq</tt> - if set to true, duplicate associated objects will be ignored by accessors and query methods
      # * <tt>:finder_sql</tt> - overwrite the default generated SQL used to fetch the association with a manual one
      # * <tt>:delete_sql</tt> - overwrite the default generated SQL used to remove links between the associated 
      #   classes with a manual one
      # * <tt>:insert_sql</tt> - overwrite the default generated SQL used to add links between the associated classes
      #   with a manual one
      #
      # Option examples:
      #   has_and_belongs_to_many :projects
      #   has_and_belongs_to_many :nations, :class_name => "Country"
      #   has_and_belongs_to_many :categories, :join_table => "prods_cats"
      def has_and_belongs_to_many(association_id, options = {})
        validate_options([ :class_name, :table_name, :foreign_key, :association_foreign_key, :conditions,
                           :join_table, :finder_sql, :delete_sql, :insert_sql, :order, :uniq ], options.keys)
        association_name, association_class_name, association_class_primary_key_name =
              associate_identification(association_id, options[:class_name], options[:foreign_key])

        require_association_class(association_class_name)

        options[:join_table] ||= join_table_name(undecorated_table_name(self.to_s), undecorated_table_name(association_class_name))

        add_multiple_associated_save_callbacks(association_name)
      
        collection_accessor_methods(association_name, association_class_name, association_class_primary_key_name, options, HasAndBelongsToManyAssociation)

        before_destroy_sql = "DELETE FROM #{options[:join_table]} WHERE #{association_class_primary_key_name} = \\\#{self.quoted_id}"
        module_eval(%{before_destroy "self.connection.delete(%{#{before_destroy_sql}})"}) # "
        
        # deprecated api
        deprecated_collection_count_method(association_name)
        deprecated_add_association_relation(association_name)
        deprecated_remove_association_relation(association_name)
        deprecated_has_collection_method(association_name)
      end

      private
        # Raises an exception if an invalid option has been specified to prevent misspellings from slipping through 
        def validate_options(valid_option_keys, supplied_option_keys)
          unknown_option_keys = supplied_option_keys - valid_option_keys
          raise(ActiveRecord::ActiveRecordError, "Unknown options: #{unknown_option_keys}") unless unknown_option_keys.empty?
        end
        
        def join_table_name(first_table_name, second_table_name)
          if first_table_name < second_table_name
            join_table = "#{first_table_name}_#{second_table_name}"
          else
            join_table = "#{second_table_name}_#{first_table_name}"
          end

          table_name_prefix + join_table + table_name_suffix
        end
        
        def associate_identification(association_id, association_class_name, foreign_key, plural = true)
          if association_class_name !~ /::/
            association_class_name = type_name_with_module(
              association_class_name || 
                Inflector.camelize(plural ? Inflector.singularize(association_id.id2name) : association_id.id2name)
            )
          end

          primary_key_name = foreign_key || Inflector.underscore(Inflector.demodulize(name)) + "_id"
        
          return association_id.id2name, association_class_name, primary_key_name
        end
        
        def association_accessor_methods(association_name, association_class_name, association_class_primary_key_name, options, association_proxy_class)
          define_method(association_name) do |*params|
            force_reload = params.first unless params.empty?
            association = instance_variable_get("@#{association_name}")
            if association.nil? or force_reload
              association = association_proxy_class.new(self,
                association_name, association_class_name,
                association_class_primary_key_name, options)
              retval = association.reload
              unless retval.nil?
                instance_variable_set("@#{association_name}", association)
              else
                instance_variable_set("@#{association_name}", nil)
                return nil
              end
            end
            association
          end

          define_method("#{association_name}=") do |new_value|
            association = instance_variable_get("@#{association_name}")
            if association.nil?
              association = association_proxy_class.new(self,
                association_name, association_class_name,
                association_class_primary_key_name, options)
            end
            association.replace(new_value)
            unless new_value.nil?
              instance_variable_set("@#{association_name}", association)
            else
              instance_variable_set("@#{association_name}", nil)
              return nil
            end
            association
          end

          define_method("set_#{association_name}_target") do |target|
            return if target.nil?
            association = association_proxy_class.new(self,
              association_name, association_class_name,
              association_class_primary_key_name, options)
            association.target = target
            instance_variable_set("@#{association_name}", association)
          end
        end

        def collection_accessor_methods(association_name, association_class_name, association_class_primary_key_name, options, association_proxy_class)
          define_method(association_name) do |*params|
            force_reload = params.first unless params.empty?
            association = instance_variable_get("@#{association_name}")
            unless association.respond_to?(:loaded?)
              association = association_proxy_class.new(self,
                association_name, association_class_name,
                association_class_primary_key_name, options)
              instance_variable_set("@#{association_name}", association)
            end
            association.reload if force_reload
            association
          end

          define_method("#{association_name}=") do |new_value|
            association = instance_variable_get("@#{association_name}")
            unless association.respond_to?(:loaded?)
              association = association_proxy_class.new(self,
                association_name, association_class_name,
                association_class_primary_key_name, options)
              instance_variable_set("@#{association_name}", association)
            end
            association.replace(new_value)
            association
          end
        end

        def require_association_class(class_name)
          require_association(Inflector.underscore(class_name)) if class_name
        end

        def add_multiple_associated_save_callbacks(association_name)
          module_eval do
            before_save <<-end_eval
              @new_record_before_save = new_record?
              association = instance_variable_get("@#{association_name}")
              if association.respond_to?(:loaded?)
                if new_record?
                  records_to_save = association
                else
                  records_to_save = association.select{ |record| record.new_record? }
                end
                records_to_save.inject(true) do |result,record|
                  result &&= record.valid?
                end
              end
            end_eval
          end

          module_eval do
            after_save <<-end_eval
              association = instance_variable_get("@#{association_name}")
              if association.respond_to?(:loaded?)
                if @new_record_before_save
                  records_to_save = association
                else
                  records_to_save = association.select{ |record| record.new_record? }
                end
                records_to_save.each{ |record| association.send(:insert_record, record) }
                association.send(:construct_sql)   # reconstruct the SQL queries now that we know the owner's id
              end
            end_eval
          end
        end

        def association_constructor_method(constructor, association_name, association_class_name, association_class_primary_key_name, options, association_proxy_class)
          define_method("#{constructor}_#{association_name}") do |*params|
            attributees = params.first unless params.empty?
            association = instance_variable_get("@#{association_name}")

            if association.nil?
              association = association_proxy_class.new(self,
                association_name, association_class_name,
                association_class_primary_key_name, options)
              instance_variable_set("@#{association_name}", association)
            end

            association.send(constructor, attributees)
          end
        end

        def find_with_associations(options = {})
          reflections          = reflect_on_included_associations(options[:include])
          schema_abbreviations = generate_schema_abbreviations(reflections)
          primary_key_table    = generate_primary_key_table(reflections, schema_abbreviations)

          rows    = select_all_rows(options, schema_abbreviations, reflections)
          records = extract_and_instantiate_records(schema_abbreviations, rows)

          assign_associations_to_records(rows, records, reflections, schema_abbreviations, primary_key_table)
          
          return records
        end

        def assign_associations_to_records(rows, records, reflections, schema_abbreviations, primary_key_table)
          records.each do |record|
            reflections.each do |reflection|
              case reflection.macro
                when :has_many, :has_and_belongs_to_many
                  record.send(reflection.name).target = 
                    extract_association_for_record(record, schema_abbreviations, primary_key_table, rows, reflection)
                when :has_one, :belongs_to
                  record.send(
                    "set_#{reflection.name}_target", 
                    extract_association_for_record(record, schema_abbreviations, primary_key_table, rows, reflection).first
                  )
              end
            end
          end
        end
        
        def generate_schema_abbreviations(reflections)
          schema = [ [ table_name, columns.collect { |c| c.name } ] ]
          schema += reflections.collect { |r| [ r.klass.table_name, r.klass.columns.collect { |c| c.name } ] }

          schema_abbreviations = {}
          schema.each_with_index do |table_and_columns, i|
            table, columns = table_and_columns
            columns.each_with_index { |column, j| schema_abbreviations["t#{i}_r#{j}"] = [ table, column ] }
          end
          
          return schema_abbreviations
        end

        def generate_primary_key_table(reflections, schema_abbreviations)
          primary_key_lookup_table = {}
          primary_key_lookup_table[table_name] = 
            schema_abbreviations.find { |cn, tc| tc == [ table_name, primary_key ] }.first

          reflections.collect do |reflection| 
            primary_key_lookup_table[reflection.klass.table_name] = schema_abbreviations.find { |cn, tc| 
              tc == [ reflection.klass.table_name, reflection.klass.primary_key ]
            }.first
          end
          
          return primary_key_lookup_table
        end


        def construct_finder_sql_with_included_associations(options, schema_abbreviations, reflections)
          habtm_associations = reflections.find_all { |r| r.macro == :has_and_belongs_to_many }

          sql = "SELECT #{column_aliases(schema_abbreviations)} FROM #{table_name} "
          sql << reflections.collect { |reflection| association_join(reflection) }.to_s
          sql << "#{options[:joins]} " if options[:joins]
          add_conditions!(sql, options[:conditions])
          sql << "ORDER BY #{options[:order]} " if options[:order]
          
          return sanitize_sql(sql)
        end

        def column_aliases(schema_abbreviations)
          schema_abbreviations.collect { |cn, tc| "#{tc.join(".")} AS #{cn}" }.join(", ")
        end

        def association_join(reflection)
          case reflection.macro
            when :has_and_belongs_to_many
              " LEFT OUTER JOIN #{reflection.options[:join_table]} ON " +
              "#{reflection.options[:join_table]}.#{reflection.options[:foreign_key] || table_name.classify.foreign_key} = " +
              "#{table_name}.#{primary_key} " +
              " LEFT OUTER JOIN #{reflection.klass.table_name} ON " +
              "#{reflection.options[:join_table]}.#{reflection.options[:associated_foreign_key] || reflection.klass.table_name.classify.foreign_key} = " +
              "#{reflection.klass.table_name}.#{reflection.klass.primary_key} "
            when :has_many, :has_one
              " LEFT OUTER JOIN #{reflection.klass.table_name} ON " +
              "#{reflection.klass.table_name}.#{reflection.options[:foreign_key] || table_name.classify.foreign_key} = " +
              "#{table_name}.#{primary_key} "
            when :belongs_to
              " LEFT OUTER JOIN #{reflection.klass.table_name} ON " +
              "#{reflection.klass.table_name}.#{reflection.klass.primary_key} = " +
              "#{table_name}.#{reflection.options[:foreign_key] || reflection.klass.table_name.classify.foreign_key} "
            else
              ""
          end          
        end


        def extract_and_instantiate_records(schema_abbreviations, rows)
          rows.collect { |row| instantiate(extract_record(schema_abbreviations, table_name, row)) }.uniq
        end

        def extract_association_for_record(record, schema_abbreviations, primary_key_table, rows, reflection)
          association = rows.collect do |row|
            if row[primary_key_table[table_name]].to_s == record.id.to_s && !row[primary_key_table[reflection.klass.table_name]].nil?
              reflection.klass.send(:instantiate, extract_record(schema_abbreviations, reflection.klass.table_name, row))
            end
          end

          return association.uniq.compact
        end

        def extract_record(schema_abbreviations, table_name, row)
          row.inject({}) do |record, pair|
            prefix, column_name = schema_abbreviations[pair.first]
            record[column_name] = pair.last if prefix == table_name
            record
          end
        end

        
        def reflect_on_included_associations(associations)
          [ associations ].flatten.collect { |association| reflect_on_association(association) }
        end
        
        def select_all_rows(options, schema_abbreviations, reflections)
          connection.select_all(
            construct_finder_sql_with_included_associations(options, schema_abbreviations, reflections), 
            "#{name} Load Including Associations"
          )
        end
    end
  end
end
