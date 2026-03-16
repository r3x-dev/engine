module R3x
  module Services
    class RssParser
      def parse(body, source_url:)
        doc = Nokogiri::XML(body)

        doc.xpath("//item").filter_map do |item|
          url = item.at_xpath("./link")&.text&.strip
          next if url.blank?

          content = [
            item.at_xpath("./description")&.text,
            item.at_xpath("./*[local-name()='encoded']")&.text
          ].compact.join(" ")

          {
            "source_type" => "rss",
            "source_url" => source_url,
            "url" => url,
            "body" => html_to_text(content),
            "lang" => "pt",
            "title" => item.at_xpath("./title")&.text&.strip,
            "published_at" => item.at_xpath("./pubDate")&.text&.strip
          }
        end
      end

      private

      def html_to_text(content)
        Nokogiri::HTML.fragment(content.to_s).text.gsub(/\s+/, " ").strip
      end
    end
  end
end
