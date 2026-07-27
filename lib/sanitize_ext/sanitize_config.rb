# frozen_string_literal: true

class Sanitize
  module Config
    HTTP_PROTOCOLS = %w(
      http
      https
    ).freeze

    LINK_PROTOCOLS = %w(
      http
      https
      dat
      dweb
      ipfs
      ipns
      ssb
      gopher
      xmpp
      magnet
      gemini
    ).freeze

    ALLOWED_CLASS_TRANSFORMER = lambda do |env|
      node = env[:node]
      class_list = node['class']&.split(/[\t\n\f\r ]/)

      return unless class_list

      class_list.keep_if do |e|
        next true if /^(h|p|u|dt|e)-/.match?(e) # microformats classes
        next true if /^(mention|hashtag)$/.match?(e) # semantic classes
        next true if /^(ellipsis|invisible)$/.match?(e) # link formatting classes
        next true if e == 'quote-inline'
      end

      node['class'] = class_list.join(' ')
    end

    IMG_TAG_TRANSFORMER = lambda do |env|
      node = env[:node]

      return unless env[:node_name] == 'img'

      node.name = 'a'

      node['href'] = node['src']
      if node['alt'].present?
        node.content = "[🖼  #{node['alt']}]"
      else
        url = node['href']
        prefix = url.match(%r{\Ahttps?://(www\.)?}).to_s
        text   = url[prefix.length, 30]
        text += '…' if url.length - prefix.length > 30
        node.content = "[🖼  #{text}]"
      end
    end

    TRANSLATE_TRANSFORMER = lambda do |env|
      node = env[:node]
      node.remove_attribute('translate') unless node['translate'] == 'no'
    end

    UNSUPPORTED_HREF_TRANSFORMER = lambda do |env|
      return unless env[:node_name] == 'a'

      current_node = env[:node]

      scheme = if current_node['href'] =~ Sanitize::REGEX_PROTOCOL
                 Regexp.last_match(1).downcase
               else
                 :relative
               end

      current_node.replace(current_node.document.create_text_node(current_node.text)) unless LINK_PROTOCOLS.include?(scheme)
    end

    # We assume that incomming <math> nodes are of the form
    # <math><semantics>...<annotation>...</annotation></semantics></math>
    # according to the [FEP]. We try to grab the most relevant plain-text
    # annotation from the semantics node, and use it to display a representation
    # of the mathematics.
    #
    # FEP: https://codeberg.org/fediverse/fep/src/branch/main/fep/dc88/fep-dc88.md
    MATH_TRANSFORMER = lambda do |env|
      math = env[:node]
      return if env[:is_allowlisted]
      return unless math.element? && env[:node_name] == 'math'

      semantics = math.element_children[0]
      return if semantics.nil? || semantics.name != 'semantics'

      # next, we find the plain-text description
      is_annotation_with_encoding = lambda do |encoding, node|
        return false unless node.name == 'annotation'

        encoding_attr = node.attributes['encoding']
        return false if encoding_attr.nil?

        encoding_attr.value == encoding
      end

      annotation = semantics.children.find(&is_annotation_with_encoding.curry['application/x-tex'])
      if annotation
        text = if math.attributes['display']&.value == 'block'
                 "$$#{annotation.text}$$"
               else
                 "$#{annotation.text}$"
               end
        math.replace(math.document.create_text_node(text))
        return
      end
      # Don't bother surrounding 'text/plain' annotations with dollar signs,
      # since it isn't LaTeX
      annotation = semantics.children.find(&is_annotation_with_encoding.curry['text/plain'])
      math.replace(math.document.create_text_node(annotation.text)) unless annotation.nil?
    end

    MASTODON_STRICT = freeze_config(
      elements: %w(p br span a abbr del s pre blockquote code b strong u sub sup i em h1 h2 h3 h4 h5 ul ol li ruby rt rp),

      attributes: {
        :all => %w(lang),
        'a' => %w(href rel class title translate),
        'abbr' => %w(title),
        'span' => %w(class translate),
        'blockquote' => %w(cite),
        'ol' => %w(start reversed),
        'li' => %w(value),
        'p' => %w(class),
      },

      add_attributes: {
        'a' => {
          'rel' => 'nofollow noopener',
          'target' => '_blank',
        },
      },

      protocols: {
        'a' => { 'href' => LINK_PROTOCOLS },
        'blockquote' => { 'cite' => LINK_PROTOCOLS },
      },

      transformers: [
        ALLOWED_CLASS_TRANSFORMER,
        IMG_TAG_TRANSFORMER,
        TRANSLATE_TRANSFORMER,
        MATH_TRANSFORMER,
        UNSUPPORTED_HREF_TRANSFORMER,
      ]
    )

    MASTODON_OEMBED = freeze_config(
      elements: %w(audio iframe source video),

      attributes: {
        'audio' => %w(controls),
        'iframe' => %w(allowfullscreen frameborder height scrolling src width),
        'source' => %w(src type),
        'video' => %w(controls height loop width),
      },

      protocols: {
        'iframe' => { 'src' => HTTP_PROTOCOLS },
        'source' => { 'src' => HTTP_PROTOCOLS },
      },

      add_attributes: {
        'iframe' => { 'sandbox' => 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-forms' },
      }
    )

    LINK_REL_TRANSFORMER = lambda do |env|
      return unless env[:node_name] == 'a' && env[:node]['href']

      node = env[:node]

      rel = (node['rel'] || '').split & ['tag']
      rel += %w(nofollow noopener) unless TagManager.instance.local_url?(node['href'])

      if rel.empty?
        node.remove_attribute('rel')
      else
        node['rel'] = rel.join(' ')
      end
    end

    LINK_TARGET_TRANSFORMER = lambda do |env|
      return unless env[:node_name] == 'a' && env[:node]['href']

      node = env[:node]
      if node['target'] != '_blank' && TagManager.instance.local_url?(node['href'])
        node.remove_attribute('target')
      else
        node['target'] = '_blank'
      end
    end

    BOARD_ANNOUNCEMENT_CLASSES = /\A(
      language-[\w+\#-]+ |
      markdown-alert(-(note|tip|important|warning|caution|title))? |
      contains-task-list |
      task-list-item
    )\z/x

    BOARD_ANNOUNCEMENT_CLASS_TRANSFORMER = lambda do |env|
      node = env[:node]
      class_list = node['class']&.split(/[\t\n\f\r ]/)

      return unless class_list

      class_list.keep_if do |e|
        next true if /^(h|p|u|dt|e)-/.match?(e) # microformats classes
        next true if /^(mention|hashtag)$/.match?(e) # semantic classes
        next true if /^(ellipsis|invisible)$/.match?(e) # link formatting classes
        next true if e == 'quote-inline'
        next true if BOARD_ANNOUNCEMENT_CLASSES.match?(e)
      end

      node['class'] = class_list.join(' ')
    end

    BOARD_ANNOUNCEMENT_INPUT_TRANSFORMER = lambda do |env|
      return unless env[:node_name] == 'input'

      node = env[:node]

      if node['type']&.downcase == 'checkbox'
        node['disabled'] = 'disabled'
        node.remove_attribute('name')
        node.remove_attribute('value')
      else
        node.unlink
      end
    end

    BOARD_ANNOUNCEMENT_CSS_PROPERTIES = %w(
      color
      background-color
      text-align
      text-decoration
      text-decoration-line
      text-decoration-color
      text-decoration-style
      font-weight
      font-style
      font-size
      border
      border-top
      border-right
      border-bottom
      border-left
      border-width
      border-style
      border-color
      border-radius
      padding
      padding-top
      padding-right
      padding-bottom
      padding-left
      margin
      margin-top
      margin-right
      margin-bottom
      margin-left
    ).freeze

    BOARD_ANNOUNCEMENT = freeze_config MASTODON_STRICT.merge(
      elements: MASTODON_STRICT[:elements] + %w(img hr table thead tbody tfoot tr th td caption p div h6 mark kbd ins small input details summary dl dt dd),

      attributes: merge(
        MASTODON_STRICT[:attributes],
        :all => %w(lang style),
        'img' => %w(src alt title style),
        'td' => %w(colspan rowspan align style),
        'th' => %w(colspan rowspan scope align style),
        'p' => %w(class align style),
        'div' => %w(class align style),
        'ul' => %w(class),
        'ol' => %w(start reversed class),
        'li' => %w(value class),
        'code' => %w(class),
        'pre' => %w(class),
        'input' => %w(type checked disabled),
        'details' => %w(open),
        'span' => %w(class translate style)
      ),

      protocols: merge(
        MASTODON_STRICT[:protocols],
        'img' => { 'src' => HTTP_PROTOCOLS }
      ),

      css: {
        allow_comments: false,
        allow_hacks: false,
        properties: BOARD_ANNOUNCEMENT_CSS_PROPERTIES,
      },

      transformers: [
        BOARD_ANNOUNCEMENT_CLASS_TRANSFORMER,
        BOARD_ANNOUNCEMENT_INPUT_TRANSFORMER,
        TRANSLATE_TRANSFORMER,
        UNSUPPORTED_HREF_TRANSFORMER,
        LINK_REL_TRANSFORMER,
        LINK_TARGET_TRANSFORMER,
      ]
    )

    MASTODON_OUTGOING = freeze_config MASTODON_STRICT.merge(
      attributes: merge(
        MASTODON_STRICT[:attributes],
        'a' => %w(href rel class title target translate)
      ),

      add_attributes: {},

      transformers: [
        ALLOWED_CLASS_TRANSFORMER,
        IMG_TAG_TRANSFORMER,
        TRANSLATE_TRANSFORMER,
        UNSUPPORTED_HREF_TRANSFORMER,
        LINK_REL_TRANSFORMER,
        LINK_TARGET_TRANSFORMER,
      ]
    )
  end
end
