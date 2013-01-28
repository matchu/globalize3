module Globalize
  module ActiveRecord
    class Adapter
      # The cache caches attributes that already were looked up for read access.
      # The stash keeps track of new or changed values that need to be saved.
      attr_accessor :record, :stash, :translations
      private :record=, :stash=

      delegate :translation_class, :to => :'record.class'

      def initialize(record)
        self.record = record
        self.stash = Attributes.new
      end

      def fetch_stash(locale, name)
        value = stash.read(locale, name)
        return value if value
        return nil
      end

      def stash_contains?(locale, name)
        stash.contains?(locale, name)
      end

      def fetch(locale, name)
        record.globalize_fallbacks(locale).each do |fallback|
          value = stash.contains?(fallback, name) ? fetch_stash(fallback, name) : fetch_attribute(fallback, name)

          unless fallbacks_for?(value)
            set_metadata(value, :locale => fallback, :requested_locale => locale)
            return value
          end
        end

        return nil
      end

      def write(locale, name, value)
        stash.write(locale, name, value)
      end

      def save_translations!
        # If the translations are already loaded, organize them by ID for fast
        # retrieval later.
        if record.translations.loaded?
          loaded_translations_by_locale = {}
          record.translations.each do |t|
            loaded_translations_by_locale[t.locale.to_s] = t
          end
        end
        
        stash.each do |locale, attrs|
          if attrs.any?
            locale = locale.to_s
            
            if record.translations.loaded?
              # Since the translations are already loaded, then we can avoid
              # SELECT queries entirely: if the translation for this locale
              # already exists, it's in the hash, so use that record - or, if
              # it doesn't exist yet, build the new record and it'll be
              # automatically added to the translations relation.
              translation = loaded_translations_by_locale[locale] ||
                record.translations.build(:locale => locale)
            else
              # The translations aren't already loaded so we're stuck with
              # loading them one-by-one. This isn't really so bad if we're only
              # updating one translation, but, if this query gets called
              # multiple times, that's a hint that you should probably be
              # preloading them. (But maybe you don't want to if you're only
              # updating, say, 3 out of 1000 translations. Whatever.)
              translation = record.translations.find_or_initialize_by_locale(locale)
            end
            attrs.each { |name, value| translation[name] = value }
            translation.save!
          end
        end

        reset
      end

      def reset
        stash.clear
      end

    protected

      def type_cast(name, value)
        if value.nil?
          nil
        elsif column = column_for_attribute(name)
          column.type_cast(value)
        else
          value
        end
      end

      def column_for_attribute(name)
        translation_class.columns_hash[name.to_s]
      end

      def unserializable_attribute?(name, column)
        column.text? && translation_class.serialized_attributes[name.to_s]
      end

      def fetch_attribute(locale, name)
        translation = record.translation_for(locale, false)
        return translation && translation.send(name)
      end

      def set_metadata(object, metadata)
        object.translation_metadata.merge!(metadata) if object.respond_to?(:translation_metadata)
        object
      end

      def translation_metadata_accessor(object)
        return if obj.respond_to?(:translation_metadata)
        class << object; attr_accessor :translation_metadata end
        object.translation_metadata ||= {}
      end

      def fallbacks_for?(object)
        object.nil? || (fallbacks_for_empty_translations? && object.blank?)
      end

      def fallbacks_for_empty_translations?
        record.fallbacks_for_empty_translations
      end
    end
  end
end
