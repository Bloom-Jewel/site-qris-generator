module QRISConverter
  module Merchant
    EMVMetaInfo = Struct.new(:id, :name, :format, :length, :mandatory)
    EMVCodes = [
      EMVMetaInfo.new( 0, 'PaymentFormatIndicator', :N, 2, true),
      EMVMetaInfo.new( 1, 'InitiationMethod', :N, 2, true),
      # EMVMetaInfo.new(26, 'ProviderInformation', :ans, true, true), # len ~ 99
      # EMVMetaInfo.new(51, 'ProviderInformation', :ans, true, false), # len ~ 99
      EMVMetaInfo.new(52, 'MerchantCategoryCode', :N, 4, true),
      EMVMetaInfo.new(53, 'TransactionCurrency', :N, 3, true),
      EMVMetaInfo.new(54, 'TransactionAmount', :ans, true, false), # len ~ 13
      EMVMetaInfo.new(55, 'TransactionTipType', :N, 2, false),
      EMVMetaInfo.new(56, 'TransactionFeeValue', :ans, true, false), # 55 = 1, len ~ 13
      EMVMetaInfo.new(57, 'TransactionFeeRate', :ans, true, false), # 55 = 2, len ~ 5
      EMVMetaInfo.new(58, 'CountryCode', :ans, 2, true),
      EMVMetaInfo.new(59, 'MerchantName', :ans, true, true), # len ~ 25
      EMVMetaInfo.new(60, 'MerchantCity', :ans, true, true), # len ~ 15
      EMVMetaInfo.new(61, 'PostalCode', :ans, true, false), # len ~ 10
      EMVMetaInfo.new(62, 'AdditionalData', :S, true, false), # len ~ 99
      
      EMVMetaInfo.new(63, 'CRC', :ans, 4, true), # CRC16
    ].group_by(&:id)
      .transform_values(&:first)
      .freeze
    EMVAdditionalDataCodes = [
      EMVMetaInfo.new( 1, 'BillNumber', :ans, true, false),
      EMVMetaInfo.new( 2, 'MobileNumber', :ans, true, false),
      EMVMetaInfo.new( 3, 'StoreLabel', :ans, true, false),
      EMVMetaInfo.new( 4, 'LoyaltyNumber', :ans, true, false),
      EMVMetaInfo.new( 5, 'ReferenceLabel', :ans, true, false),
      EMVMetaInfo.new( 6, 'CustomerLabel', :ans, true, false),
      EMVMetaInfo.new( 7, 'TerminalLabel', :ans, true, false),
      EMVMetaInfo.new( 8, 'PurposeTransaction', :ans, true, false),
      EMVMetaInfo.new( 9, 'AdditionalConsumerData', :ans, true, false),
      EMVMetaInfo.new(10, 'MerchantTaxID', :ans, true, false),
      EMVMetaInfo.new(11, 'MerchantChannel', :ans, 3, false),
    ].group_by(&:id)
      .transform_values(&:first)
      .freeze
    
    module EMVCompatibleData
      def to_s; to_emv; end
    end
    module EMVContainer
      def [](key)
        tags.find do |tag| tag.code == key end
      end
      def debug_emv
        content = []
        to_h.values.flatten.each do |tag|
          line = tag.debug_emv
          if EMVContainer === tag then
            content << sprintf("> %02d: (%02d)", tag.code, tag.to_emv.size - 4)
            line = line.split($/).map{|x| "  " + x }.join($/)
          end
          content << line
        end
        content.join($/)
      end
      def to_emv
        content = to_h.values.flatten.map(&:to_emv).join('')
        sprintf("%02d%02d%s", code, content.size, content)
      end
      def _key_sorter(code); code; end
      def _data_selector(code, data); [code, data]; end
      def to_h
        tags.sort_by do |data|
          c = data.code
          next 100 if c == 63
          c
        end.group_by do |data| _key_sorter(data.code) end
          .map do |code, data| _data_selector(code, data); end
          .to_h
      end
      prepend EMVCompatibleData
    end
    
    EMVTag = Struct.new(:code, :content) do
      def debug_emv
        sprintf('- %02d: (%02d) %s', code, content.to_s.size, content)
      end
      def to_emv
        sprintf("%02d%02d%s", code, content.to_s.size, content)
      end
      prepend EMVCompatibleData
    end
    EMVMerchantInfo = Struct.new(:code, :tags) do
      include EMVContainer
      private
      def _key_sorter(code)
        case code
        when 0
          'Identifier'
        else
          code
        end
      end
    end
    EMVExtraInfo = Struct.new(:code, :tags) do
      include EMVContainer
      def _key_sorter(code)
        if EMVAdditionalDataCodes.include?(code) then
          EMVAdditionalDataCodes[code].name
        else
          code
        end
      end
    end
    
    class EMVRoot
      attr_reader :tags
      def initialize
        @tags = []
      end
      private
      def _key_sorter(code)
        if EMVCodes.include?(code) then
          EMVCodes[code].name
        elsif (02..51) === code then
          'MerchantProviderData'
        else
          code
        end
      end
      def _data_selector(code, data)
        if 'MerchantProviderData' == code then
          [code, data]
        else
          [code, data.first]
        end
      end
      def _calc_crc16(str)
        crc = 0xffff
        str.each_byte do |c|
          crc = crc ^ (c << 8)
          8.times do
            crc = (crc & 0x8000).nonzero? ?
              (crc << 1) ^ 0x1021 : (crc << 1)
          end
        end
        sprintf("%04X", crc & 0xffff)
      end
      public
      def static_code!
        @tags.reject! do |tag| [1, 54].include?(tag.code) end
        @tags << EMVTag.new(1, 11)
        self
      end
      def dynamic_code! value
        @tags.reject! do |tag| [1, 54].include?(tag.code) end
        @tags << EMVTag.new(1, 12)
        @tags << EMVTag.new(54, value.to_s)
        self
      end
      def set_fee(type, value=nil)
        @tags.reject! do |tag| [55, 56, 57].include?(tag.code) end
        case type
        when false
          @tags << EMVTag.new(55, '01')
        when :fixed
          @tags << EMVTag.new(55, '02')
          @tags << EMVTag.new(56, (value || '0.0').to_s)
        when :rate
          @tags << EMVTag.new(55, '03')
          @tags << EMVTag.new(57, (value || '0.0').to_s)
        end
        self
      end
      
      def to_emv
        content = to_h.values.flatten.map(&:to_emv)
        content << EMVTag.new(63, _calc_crc16(content.join('') + '6304'))
        content.join('')
      end
      def to_h
        @tags.reject! do |tag| tag.code == 63 end
        super
      end
      include EMVContainer
    end
    def self.parse_str(container, str, parent: nil)
      container.tags.clear
      i = 0
      while i < str.length
        code = str[i, 2].to_i(10)
        len  = str[i+2, 2].to_i(10)
        i += 4
        case parent
        when 26..51
          content = str[i, len]
        when nil
          case code
          when 2..51
            content = EMVMerchantInfo.new(code, [])
            self.parse_str(content, str[i, len], parent: code)
          when 62
            content = EMVExtraInfo.new(code, [])
            self.parse_str(content, str[i, len], parent: code)
          else
            content = str[i, len]
          end
        else
          content = str[i, len]
        end
        if EMVContainer === content then
          container.tags << content
        else
          container.tags << EMVTag.new(code, content)
        end
        i += len
        break if parent.nil? && code == 63 # EOF
      end
      container
    end
  end
end