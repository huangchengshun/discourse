# frozen_string_literal: true

require "rails_helper"

describe Chat::Publisher do
  fab!(:channel) { Fabricate(:category_channel) }
  fab!(:message_1) { Fabricate(:chat_message, chat_channel: channel) }

  describe ".publish_delete!" do
    fab!(:message_2) { Fabricate(:chat_message, chat_channel: channel) }
    before { message_2.trash! }

    it "publishes the correct data" do
      data =
        MessageBus.track_publish { described_class.publish_delete!(channel, message_2) }[0].data

      expect(data["deleted_at"]).to eq(message_2.deleted_at.iso8601(3))
      expect(data["deleted_id"]).to eq(message_2.id)
      expect(data["latest_not_deleted_message_id"]).to eq(message_1.id)
      expect(data["type"]).to eq("delete")
    end

    context "when there are no earlier messages in the channel to send as latest_not_deleted_message_id" do
      it "publishes nil" do
        data =
          MessageBus.track_publish { described_class.publish_delete!(channel, message_1) }[0].data

        expect(data["latest_not_deleted_message_id"]).to eq(nil)
      end
    end

    context "when the message is in a thread and the channel has threading_enabled" do
      before do
        SiteSetting.enable_experimental_chat_threaded_discussions = true
        thread = Fabricate(:chat_thread, channel: channel)
        message_1.update!(thread: thread)
        message_2.update!(thread: thread)
        channel.update!(threading_enabled: true)
      end

      it "publishes the correct latest not deleted message id" do
        data =
          MessageBus.track_publish { described_class.publish_delete!(channel, message_2) }[0].data

        expect(data["deleted_at"]).to eq(message_2.deleted_at.iso8601(3))
        expect(data["deleted_id"]).to eq(message_2.id)
        expect(data["latest_not_deleted_message_id"]).to eq(message_1.id)
        expect(data["type"]).to eq("delete")
      end
    end
  end

  describe ".publish_refresh!" do
    it "publishes the message" do
      data =
        MessageBus.track_publish { described_class.publish_refresh!(channel, message_1) }[0].data

      expect(data["chat_message"]["id"]).to eq(message_1.id)
      expect(data["type"]).to eq("refresh")
    end
  end

  describe ".calculate_publish_targets" do
    context "when enable_experimental_chat_threaded_discussions is false" do
      before { SiteSetting.enable_experimental_chat_threaded_discussions = false }

      context "when the message is the original message of a thread" do
        fab!(:thread) { Fabricate(:chat_thread, original_message: message_1, channel: channel) }

        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end

      context "when the message is a thread reply" do
        fab!(:thread) do
          Fabricate(
            :chat_thread,
            original_message: Fabricate(:chat_message, chat_channel: channel),
            channel: channel,
          )
        end

        before { message_1.update!(thread: thread) }

        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end

      context "when the message is not part of a thread" do
        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end
    end

    context "when threading_enabled is false for the channel" do
      before do
        SiteSetting.enable_experimental_chat_threaded_discussions = true
        channel.update!(threading_enabled: false)
      end

      context "when the message is the original message of a thread" do
        fab!(:thread) { Fabricate(:chat_thread, original_message: message_1, channel: channel) }

        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end

      context "when the message is a thread reply" do
        fab!(:thread) do
          Fabricate(
            :chat_thread,
            original_message: Fabricate(:chat_message, chat_channel: channel),
            channel: channel,
          )
        end

        before { message_1.update!(thread: thread) }

        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end

      context "when the message is not part of a thread" do
        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end
    end

    context "when enable_experimental_chat_threaded_discussions is true and threading_enabled is true for the channel" do
      before do
        channel.update!(threading_enabled: true)
        SiteSetting.enable_experimental_chat_threaded_discussions = true
      end

      context "when the message is the original message of a thread" do
        fab!(:thread) { Fabricate(:chat_thread, original_message: message_1, channel: channel) }

        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly(
            "/chat/#{channel.id}",
            "/chat/#{channel.id}/thread/#{thread.id}",
          )
        end
      end

      context "when a staged thread has been provided" do
        fab!(:thread) do
          Fabricate(
            :chat_thread,
            original_message: Fabricate(:chat_message, chat_channel: channel),
            channel: channel,
          )
        end

        before { message_1.update!(thread: thread) }

        it "generates the correct targets" do
          targets =
            described_class.calculate_publish_targets(
              channel,
              message_1,
              staged_thread_id: "stagedthreadid",
            )

          expect(targets).to contain_exactly(
            "/chat/#{channel.id}/thread/#{thread.id}",
            "/chat/#{channel.id}/thread/stagedthreadid",
          )
        end
      end

      context "when the message is a thread reply" do
        fab!(:thread) do
          Fabricate(
            :chat_thread,
            original_message: Fabricate(:chat_message, chat_channel: channel),
            channel: channel,
          )
        end

        before { message_1.update!(thread: thread) }

        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}/thread/#{thread.id}")
        end
      end

      context "when the message is not part of a thread" do
        it "generates the correct targets" do
          targets = described_class.calculate_publish_targets(channel, message_1)
          expect(targets).to contain_exactly("/chat/#{channel.id}")
        end
      end
    end
  end

  describe ".publish_new!" do
    let(:staged_id) { 999 }

    context "when the message is not a thread reply" do
      it "publishes to the new_messages_message_bus_channel" do
        messages =
          MessageBus.track_publish(described_class.new_messages_message_bus_channel(channel.id)) do
            described_class.publish_new!(channel, message_1, staged_id)
          end
        expect(messages.first.data).to eq(
          {
            channel_id: channel.id,
            message_id: message_1.id,
            user_id: message_1.user_id,
            username: message_1.user.username,
            thread_id: nil,
          },
        )
      end
    end

    context "when the message is a thread reply" do
      fab!(:thread) do
        Fabricate(
          :chat_thread,
          original_message: Fabricate(:chat_message, chat_channel: channel),
          channel: channel,
        )
      end

      before { message_1.update!(thread: thread) }

      context "if enable_experimental_chat_threaded_discussions is false" do
        before { SiteSetting.enable_experimental_chat_threaded_discussions = false }

        it "publishes to the new_messages_message_bus_channel" do
          messages =
            MessageBus.track_publish(
              described_class.new_messages_message_bus_channel(channel.id),
            ) { described_class.publish_new!(channel, message_1, staged_id) }
          expect(messages).not_to be_empty
        end
      end

      context "if enable_experimental_chat_threaded_discussions is true" do
        before { SiteSetting.enable_experimental_chat_threaded_discussions = true }

        context "if threading_enabled is false for the channel" do
          before { channel.update!(threading_enabled: false) }

          it "publishes to the new_messages_message_bus_channel" do
            messages =
              MessageBus.track_publish(
                described_class.new_messages_message_bus_channel(channel.id),
              ) { described_class.publish_new!(channel, message_1, staged_id) }
            expect(messages).not_to be_empty
          end
        end

        context "if threading_enabled is true for the channel" do
          before { channel.update!(threading_enabled: true) }

          it "does not publish to the new_messages_message_bus_channel" do
            messages =
              MessageBus.track_publish(
                described_class.new_messages_message_bus_channel(channel.id),
              ) { described_class.publish_new!(channel, message_1, staged_id) }
            expect(messages).to be_empty
          end
        end
      end
    end
  end
end
