require 'test_helper'

class RemoteArgusTest < Test::Unit::TestCase
  def setup
    @gateway = ArgusGateway.new(fixtures(:argus).slice(:site_id, :req_username, :req_password))

    @amount = 100
    @credit_card = credit_card('4000100011112224')
    @declined_card = credit_card('4000300011112220')
    @options = {
      merch_acct_id: fixtures(:argus).fetch(:merch_acct_id), # Merchant account id is required for auth and purchase
      li_prod_id_1: fixtures(:argus).fetch(:li_prod_id_1),  # Line item product id is required for auth and purchase
      billing_address: address,
      description: 'Store Purchase'
    }
    @additional_options_3ds = @options.merge(
      execute_threed: true,
      three_d_secure: {
        version: '1.0.2',
        eci: '06',
        cavv: 'AgAAAAAAAIR8CQrXcIhbQAAAAAA',
        xid: 'MDAwMDAwMDAwMDAwMDAwMzIyNzY='
      }
    )
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'APPROVED', response.message
    assert_equal 'M', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  def test_successful_purchase_with_more_options
    options = {
      order_id: '1',
      ip: '127.0.0.1',
      email: 'joe@example.com'
    }

    response = @gateway.purchase(@amount, @credit_card, @options.merge(options))
    assert_success response
    assert_equal 'APPROVED', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(505, @declined_card, @options)
    assert_failure response
    assert_match %r{DECLINED}i, response.message
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert_equal 'APPROVED', capture.message
  end

  def test_successful_authorize_and_capture_with_3ds
    assert auth = @gateway.authorize(@amount, @credit_card, @additional_options_3ds)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def test_successful_purchase_with_stored_credentials
    network_transaction_id = generate_order_id

    initial_options = @options.merge(
      stored_credential: {
        initial_transaction: true,
        reason_type: 'recurring',
        network_transaction_id: network_transaction_id
      }
    )
    initial_response = @gateway.purchase(@amount, @credit_card, initial_options)
    assert_success initial_response
    assert_equal 'APPROVED', initial_response.message

    used_options = @options.merge(
      order_id: generate_order_id,
      stored_credential: {
        initial_transaction: false,
        reason_type: 'recurring',
        network_transaction_id: network_transaction_id
      }
    )
    response = @gateway.purchase(@amount, @credit_card, used_options)
    assert_success response
    assert_equal 'APPROVED', response.message
  end

  def test_failed_authorize
    response = @gateway.authorize(505, @declined_card, @options)
    assert_failure response
    assert_match %r{DECLINED}i, response.message
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount-1, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    _response = @gateway.capture(505, auth.authorization)
    # Test gateway does not support
    # assert_failure response
    # assert_equal 'DECLINED', response.message
  end

  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert _refund = @gateway.refund(@amount, purchase.authorization)
    # Test gateway returns 'Order not settled: Please reverse'
    # assert_success refund
    # assert_equal 'REPLACE WITH SUCCESSFUL REFUND MESSAGE', refund.message
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert _refund = @gateway.refund(@amount-1, purchase.authorization)
    # Test gateway returns 'Order not settled: Please reverse'
    # assert_success refund
  end

  def test_failed_refund
    response = @gateway.refund(@amount, '')
    assert_failure response
    assert_match %r{Invalid Data}, response.message
    assert_match %r{REQUEST_REF_PO_ID}, response.message
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'APPROVED', void.message
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
    assert_match %r{Invalid Data}, response.message
    assert_match %r{REQUEST_REF_PO_ID}, response.message
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{APPROVED}, response.message
  end

  def test_failed_verify
    _response = @gateway.verify(@declined_card, @options)
    # assert_failure response
    # assert_match %r{DECLINED}, response.message
  end

  def test_invalid_login
    gateway = ArgusGateway.new(site_id: '999', req_username: 'user', req_password: 'badpass')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match %r{Invalid login}, response.message
  end

  def test_dump_transcript
    # This test will run a purchase transaction on your gateway
    # and dump a transcript of the HTTP conversation so that
    # you can use that transcript as a reference while
    # implementing your scrubbing logic.  You can delete
    # this helper after completing your scrub implementation.
    # dump_transcript_and_fail(@gateway, @amount, @credit_card, @options)
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:req_password], transcript)
  end


  private

  def generate_order_id
    (Time.now.to_f * 100).to_i.to_s
  end
end
