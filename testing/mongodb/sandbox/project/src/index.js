import { MongoClient } from "mongodb";

const client = new MongoClient(process.env.MONGODB_URI);

export async function listHabits(userId) {
  return client.db("habits").collection("entries").find({ userId }).toArray();
}
