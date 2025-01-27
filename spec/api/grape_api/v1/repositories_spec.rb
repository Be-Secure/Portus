# frozen_string_literal: true

require "rails_helper"

describe API::V1::Repositories do
  let!(:admin) { create(:admin) }
  let!(:token) { create(:application_token, user: admin) }
  let!(:public_namespace) do
    create(:namespace,
           visibility: Namespace.visibilities[:visibility_public],
           team:       create(:team))
  end

  before do
    @header = build_token_header(token)
  end

  context "GET /api/v1/repositories" do
    it "returns an empty list" do
      get "/api/v1/repositories", nil, @header

      repositories = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(repositories.length).to eq(0)
    end

    it "returns list of repositories" do
      create_list(:repository, 5, namespace: public_namespace)
      get "/api/v1/repositories", nil, @header

      repositories = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(repositories.length).to eq(5)
    end
  end

  context "GET /api/v1/repositories/:id" do
    it "returns a team" do
      repository = create(:repository, namespace: public_namespace)
      get "/api/v1/repositories/#{repository.id}", nil, @header

      repository_parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(repository_parsed["id"]).to eq(repository.id)
      expect(repository_parsed["name"]).to eq(repository.name)
      expect(repository_parsed["tags"]).to be_nil
    end

    it "returns 404 if it doesn't exist" do
      get "/api/v1/repositories/222", nil, @header

      expect(response).to have_http_status(:not_found)
    end
  end

  context "GET /api/v1/repositories/:id/tags" do
    it "returns list of reposiroty tags" do
      repository = create(:repository, namespace: public_namespace)
      create(:tag, name: "taggg", repository: repository, digest: "1", author: admin)
      create_list(:tag, 4, repository: repository, digest: "123123", author: admin)
      get "/api/v1/repositories/#{repository.id}/tags", nil, @header

      tags = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(tags.length).to eq(5)
    end
  end

  context "GET /api/v1/repositories/:id/tags/:tag_id" do
    it "returns list of reposiroty tags" do
      repository = create(:repository, namespace: public_namespace)
      tag = create(:tag, name: "taggg", repository: repository, digest: "1", author: admin)
      get "/api/v1/repositories/#{repository.id}/tags/#{tag.id}", nil, @header

      tag_parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(tag_parsed["id"]).to eq(tag.id)
      expect(tag_parsed["name"]).to eq(tag.name)
    end
  end

  context "GET /api/v1/repositories/:id/tags/grouped" do
    it "returns list of reposiroty tags grouped" do
      repository = create(:repository, namespace: public_namespace)
      create(:tag, name: "taggg", repository: repository, digest: "1", author: admin)
      create_list(:tag, 4, repository: repository, digest: "123123", author: admin)
      get "/api/v1/repositories/#{repository.id}/tags/grouped", nil, @header

      tags = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(tags.length).to eq(2)

      # The order depends on the update_at property, which might be slightly
      # different depending on how fast creation happened on these tests.
      if tags[0].length == 1
        first  = 0
        second = 1
      else
        first  = 1
        second = 0
      end

      expect(tags[first].length).to eq(1)
      expect(tags[second].length).to eq(4)
    end
  end

  context "DELETE /api/v1/repositories/:id" do
    before do
      APP_CONFIG["delete"]["enabled"] = true
    end

    it "deletes repository" do
      repository = create(:repository, namespace: public_namespace)
      delete "/api/v1/repositories/#{repository.id}", nil, @header
      expect(response).to have_http_status(:no_content)
      expect { Repository.find(repository.id) }.to raise_exception(ActiveRecord::RecordNotFound)
    end

    it "forbids deletion of repository (delete disabled)" do
      APP_CONFIG["delete"]["enabled"] = false
      repository = create(:repository, namespace: public_namespace)
      delete "/api/v1/repositories/#{repository.id}", nil, @header
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 if unable to remove dependent tag" do
      allow_any_instance_of(Portus::RegistryClient).to receive(:delete) do
        raise ::Portus::RegistryClient::RegistryError, "I AM ERROR."
      end

      repository = create(:repository, namespace: public_namespace)
      create(:tag, name: "taggg", repository: repository, digest: "1", author: admin)
      delete "/api/v1/repositories/#{repository.id}", nil, @header
      body = JSON.parse(response.body)
      expect(body["message"]).to include("could not remove taggg tag")
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 if unable to remove repository" do
      repository = create(:repository, namespace: public_namespace)
      allow_any_instance_of(Repository).to receive(:destroy).and_return(false)

      delete "/api/v1/repositories/#{repository.id}", nil, @header
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns status 404" do
      delete "/api/v1/repositories/999", nil, @header
      expect(response).to have_http_status(:not_found)
    end
  end
end
