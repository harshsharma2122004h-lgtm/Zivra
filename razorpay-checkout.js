// ZIVRA Razorpay checkout: intercept only online submissions; COD keeps the existing flow.
(function () {
  const form = document.getElementById('checkoutForm');
  if (!form) return;
  const moneyText = n => '₹' + Number(n || 0).toLocaleString('en-IN');
  let paymentInProgress = false;
  form.addEventListener('submit', async function (event) {
    const fd = new FormData(form);
    if (fd.get('payment') !== 'upi') return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (paymentInProgress) return;
    paymentInProgress = true;
    const supabase = window.zivraSupabase;
    if (!supabase) { paymentInProgress = false; alert('Store connection is not ready. Please refresh and try again.'); return; }
    if (!window.Razorpay) { paymentInProgress = false; alert('Secure payment window could not load. Please refresh and try again.'); return; }
    if (!Array.isArray(window.cartItems) && typeof cartItems === 'undefined') {
      paymentInProgress = false; alert('Your bag could not be read. Please refresh and try again.'); return;
    }
    const bag = typeof cartItems !== 'undefined' ? cartItems : window.cartItems;
    if (!bag || !bag.length || bag.some(x => !x.productId)) {
      paymentInProgress = false; alert('Please add available live products to your bag before paying.'); return;
    }
    const button = document.getElementById('placeOrderBtn');
    if (button) { button.disabled = true; button.textContent = 'CONNECTING TO PAYMENT…'; }
    const customer = {
      name: String(fd.get('fullName') || ''), email: String(fd.get('email') || ''),
      phone: String(fd.get('phone') || ''), address: String(fd.get('address') || ''),
      city: String(fd.get('city') || ''), pincode: String(fd.get('pincode') || '')
    };
    const items = bag.map(x => ({
      product_id: x.productId, quantity: Number(x.qty),
      size: x.size || 'M', color: x.color || 'Default'
    }));
    try {
      const { data: created, error: createError } = await supabase.functions.invoke('create-razorpay-order', { body: { items } });
      if (createError) throw createError;
      if (!created || !created.razorpay_order_id || !created.key_id) throw new Error(created?.error || 'Could not start online payment.');
      const checkout = new window.Razorpay({
        key: created.key_id, amount: created.amount, currency: created.currency || 'INR',
        name: 'ZIVRA', description: 'ZIVRA fashion order', order_id: created.razorpay_order_id,
        prefill: { name: customer.name, email: customer.email, contact: customer.phone },
        theme: { color: '#171717' },
        handler: async function (response) {
          try {
            const { data: verified, error: verifyError } = await supabase.functions.invoke('verify-razorpay-payment', {
              body: { ...response, customer, items }
            });
            if (verifyError) throw verifyError;
            if (!verified?.ok || !verified.order_id) throw new Error(verified?.error || 'Payment verification failed. Contact ZIVRA support before retrying.');
            let emailSent = false;
            try {
              const { error } = await supabase.functions.invoke('send-order-email', { body: { order_id: verified.order_id, type: 'received' } });
              if (error) throw error;
              emailSent = true;
            } catch (mailError) { console.warn('ZIVRA confirmation email:', mailError); }
            const setText = (id, value) => { const el = document.getElementById(id); if (el) el.textContent = value; };
            setText('cartHeading', 'Order confirmation');
            form.classList.remove('show');
            const cartContents = document.getElementById('cartContents'); if (cartContents) cartContents.style.display = 'none';
            const orderSuccess = document.getElementById('orderSuccess'); if (orderSuccess) orderSuccess.classList.add('show');
            setText('orderMessage',
              'Thank you, ' + customer.name + '. Your online payment is verified and your order ' +
              verified.order_number + ' is confirmed. Total paid: ' + moneyText(verified.total) +
              '. ' + (emailSent ? 'A confirmation email has been sent to ' + customer.email + '.' :
              'Your order is saved, but the confirmation email could not be sent.'));
            const successNote = document.querySelector('#orderSuccess .checkout-note');
            if (successNote) successNote.textContent = 'Payment status: PAID · Razorpay payment ID: ' + response.razorpay_payment_id;
            const itemsText = bag.map(x => x.name + ' · Size ' + (x.size || 'M') + ' · ' + (x.color || 'Default') + ' × ' + x.qty).join('\n');
            const address = [customer.address, customer.city, customer.pincode].filter(Boolean).join(', ');
            const emailBody = document.getElementById('customerEmailBody');
            if (emailBody) emailBody.textContent = 'Hi ' + customer.name + ',\n\nThank you for choosing ZIVRA. Your payment is verified and your order is confirmed.\n\nORDER ' + verified.order_number + '\n' + itemsText + '\n\nTotal paid: ' + moneyText(verified.total) + '\nPayment: Paid online\nDelivery to: ' + address + '\n\nWith love,\nTeam ZIVRA';
            setText('customerEmailTo', customer.email);
            setText('customerOrderId', verified.order_number);
            setText('ownerOrderId', verified.order_number);
            setText('ownerEmailBody', 'PAID ONLINE ORDER · ' + verified.order_number + '\nCustomer: ' + customer.name + '\nEmail: ' + customer.email + '\nPhone: ' + customer.phone + '\nAddress: ' + address + '\n\nItems:\n' + itemsText + '\n\nTotal paid: ' + moneyText(verified.total) + '\nRazorpay payment ID: ' + response.razorpay_payment_id);
            if (typeof cartItems !== 'undefined') { cartItems = []; if (typeof renderCart === 'function') renderCart(); }
            if (button) { button.disabled = false; button.textContent = 'PLACE ORDER →'; }
          } catch (err) {
            console.error('ZIVRA payment verification:', err);
            alert((err.message || 'Payment verification failed.') + ' Please contact ZIVRA support with payment ID: ' + response.razorpay_payment_id);
            paymentInProgress = false;
            if (button) { button.disabled = false; button.textContent = 'PLACE ORDER →'; }
          }
        },
        modal: { ondismiss: function () { paymentInProgress = false; if (button) { button.disabled = false; button.textContent = 'PLACE ORDER →'; } } }
      });
      checkout.on('payment.failed', function (failure) {
        alert(failure?.error?.description || 'Payment failed. Please try again or choose Cash on Delivery.');
        paymentInProgress = false;
        if (button) { button.disabled = false; button.textContent = 'PLACE ORDER →'; }
      });
      checkout.open();
    } catch (err) {
      paymentInProgress = false;
      console.error('ZIVRA checkout:', err);
      alert(err.message || 'Unable to start online payment. Please try again.');
      if (button) { button.disabled = false; button.textContent = 'PLACE ORDER →'; }
    }
  }, true);
})();