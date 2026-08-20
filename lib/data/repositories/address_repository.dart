import '../../core/network/api_client.dart';
import '../models/address.dart';

class AddressRepository {
  AddressRepository(this._api);
  final ApiClient _api;

  Future<List<Address>> list() async {
    final res = await _api.getPage('/customer/addresses');
    return ((res.data as List?) ?? const [])
        .map((e) => Address.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Address> add(Map<String, dynamic> body) async {
    final data = await _api.post('/customer/addresses', body: body) as Map;
    return Address.fromJson((data['address'] as Map).cast<String, dynamic>());
  }

  Future<Address> update(int id, Map<String, dynamic> body) async {
    final data = await _api.put('/customer/addresses/$id', body: body) as Map;
    return Address.fromJson((data['address'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(int id) => _api.delete('/customer/addresses/$id');
}
