import '../../../core/arch/repository.dart';
import '../../../core/store.dart';
import '../model/job.dart';
import '../model/job_profile.dart';

/// The user's job profile and saved jobs.
class JobStore {
  JobStore._();
  static final instance = JobStore._();

  final saved = PrefsRepository<String, Job>(Store.raw, 'jobs_saved', const JsonCodec(encode: _enc, decode: Job.fromJson), (j) => j.id);

  JobProfile get profile {
    final j = Store.getJson('job_profile');
    return j is Map ? JobProfile.fromJson(j) : const JobProfile();
  }

  Future<void> saveProfile(JobProfile p) => Store.setJson('job_profile', p.toJson());
}

Object _enc(Job j) => j.toJson();
