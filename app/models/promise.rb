<%# app/views/works_orders/_promises.html.erb — locals: works_order
    Header widget: the "Promise" button (next to Edit) drops down the form
    and the list of open promises with their withdraw buttons. Open-promise
    pills are rendered separately in the title row by _promise_pills. %>
<% promises = works_order.promises.by_due.to_a %>
<% live = promises.select(&:open?) %>
<% history = promises - live %>
<details class="relative" id="promises">
  <summary class="list-none cursor-pointer bg-emerald-600 hover:bg-emerald-700 text-white font-bold py-2 px-4 rounded select-none">
    🤝 Promise<%= " (#{live.size})" if live.any? %>
  </summary>
  <div class="absolute right-0 z-40 mt-2 w-80 bg-white rounded-lg shadow-xl border border-gray-200 p-4 space-y-4">
    <% if live.any? %>
      <ul class="space-y-2">
        <% live.each do |p| %>
          <li class="flex items-start justify-between gap-2 rounded-lg px-3 py-2 <%= promise_row_class(p) %>">
            <div>
              <%= promise_pill(p) %>
              <div class="text-xs text-gray-500 mt-1">
                <%= p.outstanding %> of <%= p.quantity %> still to release
                <% if p.promised_by %> · <%= p.promised_by.display_name %><% end %>
                · <%= p.created_at.strftime("%-d %b") %>
              </div>
              <% if p.note.present? %><div class="text-xs text-gray-700 mt-0.5"><%= p.note %></div><% end %>
            </div>
            <%= button_to "withdraw", cancel_promise_path(p), method: :patch,
                  form: { data: { turbo_confirm: "Withdraw this promise?" } },
                  class: "text-xs text-gray-400 hover:text-red-600 shrink-0" %>
          </li>
        <% end %>
      </ul>
    <% end %>

    <% if works_order.can_be_released? %>
      <%= form_with model: [works_order, Promise.new], local: true, data: { turbo: false }, class: "space-y-2" do |f| %>
        <div class="flex items-center gap-2">
          <%= f.number_field :quantity, value: works_order.unreleased_quantity, min: 1, max: works_order.unreleased_quantity,
                class: "w-20 rounded border-gray-300 text-sm", title: "Quantity promised" %>
          <span class="text-sm text-gray-500">by</span>
          <%= f.date_field :due_on, min: Date.current, required: true, class: "rounded border-gray-300 text-sm" %>
        </div>
        <%= f.text_field :note, placeholder: "Note (who asked, why)", class: "w-full rounded border-gray-300 text-sm" %>
        <%= f.submit "Promise", class: "w-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-bold py-1.5 px-4 rounded cursor-pointer" %>
      <% end %>
    <% else %>
      <p class="text-xs text-gray-400">Nothing left to release on this works order.</p>
    <% end %>

    <% if history.any? %>
      <details>
        <summary class="text-xs text-gray-400 cursor-pointer">Past promises (<%= history.size %>)</summary>
        <ul class="mt-2 space-y-1">
          <% history.each do |p| %>
            <li class="text-xs text-gray-500">
              <%= p.quantity %> by <%= p.due_label %> —
              <%= p.active? ? "met" : "withdrawn #{p.cancelled_at.strftime('%-d %b')}" %>
              <%= "· #{p.note}" if p.note.present? %>
            </li>
          <% end %>
        </ul>
      </details>
    <% end %>
  </div>
</details>
